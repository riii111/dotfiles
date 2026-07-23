---
name: task-orchestration
description: |
  オーケストレーションIDに紐づくタスク群を毎回読み直し、PRのmergeと依存関係から次に開始できるタスクを選び、通常の独立したCodex子セッションを重複なく作成する。
  最初のタスク開始、merge通知後の再開、開始済み・依存待ちタスクの整理に使う。
---

# Task Orchestration

一回の実行で、次に同時開始するタスクを選ぶ。subagent、`fork_thread`、Codex管理のworktreeは使わない。

## 入力値

- base: 必須
- 最大並列数: 任意。既定値は4
- ブリッジから受け取ったmerge情報: 任意
- 子セッション用SKILL: 任意。既定は「利用なし」
- 子セッションの完了方針: 任意。`manual`または`auto`。既定は`manual`
- 子セッションのmodelとthinking: 任意。指定時は下記の組み合わせから選ぶ

`manual`はreview通過後もdraft PRのままユーザーへ報告して止める。`auto`はreview通過後にReady for reviewへ変更し、最新headの全検証と必須checksを確認してmergeまで進める。`auto`は対象repositoryとtaskへ明示された場合だけ使う。

オーケストレーションIDは`codex-task-orchestrator init`で登録済みの設定から自動解決する。ユーザーへ入力を求めない。baseを過去の会話からも確定できなければ「判断が必要」として返す。

子セッションのmodelとthinkingは、明示指定があればそれを使う。指定がなければ、Issueを読み直して次から選ぶ。

- 実装に必要な情報が揃い、変更範囲が限定的: `gpt-5.6-luna` + `xhigh`
- 実装に必要な情報が揃い、複数の呼び出し元・設定・失敗経路を調べる: `gpt-5.6-terra` + `high`
- 実装に必要な情報が不足し、責務・仕様・構成などの設計判断が必要: `gpt-5.6-sol` + `medium`

## 状態管理ツール

`scripts/orchestration_state.py`を、設定と状態の読込、schema検証、開始対象の計算、ID保存に使う。これらをAIの手作業で再実装しない。

```text
python3 <skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

設定は、絶対パスの`XDG_CONFIG_HOME`または`$HOME/.config`にある`codex-task-orchestrator/config.toml`から読む。`repository`はタスク管理元、`pull_request_repositories`は成果物PRを許可するrepositoryの一覧として扱う。後者がない旧設定では`repository`だけを許可する。セッション対応表とmerge処理記録は、絶対パスの`XDG_STATE_HOME`または`$HOME/.local/state`にある`codex-task-orchestrator/<orchestration-id>/sessions.json`と`merges.json`から読む。

`context`は設定とローカル状態を検証する。失敗したら推測せず停止する。Completion Noteを含む状態の対応付けや形式はスクリプトだけが扱う。

## 開始するタスクを選ぶ

1. `context`を実行する。
2. `task_source`から、全タスクの最新本文、直接依存、現在状態、状態履歴、優先順位を毎回読み直す。ページングと依存先を省略しない。
3. 読み直した結果と確認済みの完了task IDを`plan`へ渡す。`--completed`には、ブリッジまたは`context`のmerge記録、追跡PRの`mergedAt`とmerge commit、開始前から完了していたことを初回読込と履歴で確認できるtaskだけを入れる。タスク管理元だけが後から完了になったtaskは入れない。

```json
{
  "tasks": [
    { "id": "TASK-1", "dependencies": [], "order": 0 },
    { "id": "TASK-2", "dependencies": ["TASK-1"], "order": 1 }
  ]
}
```

```text
python3 <skill-directory>/scripts/orchestration_state.py plan <orchestration-id> \
  --tasks <normalized-tasks.json> \
  --completed <task-id> \
  --max-parallelism <user override or 4>
```

`plan`の出力を次の順で実行する。

1. `resume_completion_notes`の各子セッションへ、`completion-report` SKILLを使うよう依頼する。Noteの内容は親へ表示しない。この配列が空でなければ、保存後に改めて`plan`を実行する。
2. `selected`のtaskを作成する。Goalには同じtaskの`dependency_completion_notes`をそのまま入れる。

依存の充足、Noteの保存有無、並列枠、引継ぎ項目の選別は`plan`が決める。親は出力を再計算しない。

## 子セッションを作る

`selected`の各タスクについて、必ず一つずつ次を行う。

1. `list_projects`でrepositoryに対応する保存済みprojectを一意に特定する。
2. `context`を再実行し、task IDが未登録で、対象repositoryが`pull_request_repositories`に含まれることを確認する。含まれなければ作成せず「判断が必要」とする。Goalには`plan`の`dependency_completion_notes[task ID]`をそのまま入れる。
3. `create_thread`より先に作成予約を保存する。

```text
python3 <skill-directory>/scripts/orchestration_state.py reserve-session <orchestration-id> \
  --task-id <task-id>
```

4. 選んだmodelとthinkingを指定して`create_thread`を一回だけ呼ぶ。project targetの`environment`は必ず`local`とし、promptには下記Goalを使う。通常のlocal作成は`threadId`と`hostId`を直接返す。`clientThreadId`を返すCodex管理worktreeは指定しない。
5. `threadId`を取得した直後に保存する。

```text
python3 <skill-directory>/scripts/orchestration_state.py record-session <orchestration-id> \
  --task-id <task-id> \
  --child-thread-id <thread-id>
```

6. `threadId`が返らなければ予約を残し、それ以上作成せず「判断が必要」とする。
7. 保存後に`set_thread_title`で`[<task-id>] <task title>`へ変更する。

予約後の作成失敗、ID保存、タイトル変更の失敗では同じタスクを再作成せず、保存済みの状態と失敗内容を返す。

`create_thread`がセッションを作成していないと確定でき、ユーザーが再試行を明示的に許可した場合だけ、`reserved`を解除する。タイムアウトなど結果が不明な場合には使わない。

```text
python3 <skill-directory>/scripts/orchestration_state.py release-reservation <orchestration-id> \
  --task-id <task-id>
```

## 子セッションへ渡すGoal

タイトルとGoalの両方にtask IDを含める。Goalには以下を含める。

- タスク管理元から最新本文と依存タスクを再読する
- 指定baseから`git worktree`で作業場所を作り、Codexのworktree機能を使わない
- 呼び出し元、公開境界、テスト、設定、失敗経路など二次・三次影響まで調べる
- branch名は目的を表すconventionalな英語名にし、issue番号やtask IDを含めない
- commitをConventional Commitsに従って小さく意味的にまとめる
- リポジトリ所定のlint、test、型検査、buildを通す
- 検証後にdraft PRを作る
- draft PR作成後、次を実行してローカルにPRを対応付ける
- 子セッション用SKILLの利用有無
- 子セッションの完了方針。既定の`manual`、または明示的に許可された`auto`
- `plan`が返した`dependency_completion_notes`

```text
python3 <skill-directory>/scripts/orchestration_state.py record-pr <orchestration-id> \
  --task-id <task-id> \
  --repository <owner/repository> \
  --number <pr-number>
```

PR本文にはオーケストレーター固有のtask IDや管理用markerを書かない。`record-pr`が失敗した場合は、PRを作り直さず、作成済みPRと失敗内容をユーザーへ返す。

## 停止条件

子セッションを新たに作らず「判断が必要」とする条件は以下。

- 必須入力を確定できない
- タスク管理元を完全に読み直せない、または依存関係に不足・矛盾がある
- 完了証拠が不足または矛盾している
- セッションの予約、作成、ローカル状態への保存を確認できない

## 結果

依存関係を確認した結果を先に返す。開始が1件なら、次の形式にする。

```text
依存関係をチェックした結果、並列で着手できるのは以下だったのだ。
- #<task-id>「<task title>」
完了後はdraft PRを作成して止めるのだ。
```

開始が複数件なら、着手できるtask IDとタイトルを列挙して実装開始を伝える。`manual`以外の完了方針では、実際の停止またはmerge方針を伝える。

ID、base、最大並列数、thread ID、状態、完了task、依存待ちtask、見送ったtask、予約中task、対応表は主結果の後に`補足`として返す。作成対象がない確定状態は`開始可能なタスクなし`とする。
