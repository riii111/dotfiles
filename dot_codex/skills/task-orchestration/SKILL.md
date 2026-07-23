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

`context`は設定、セッション対応、完了判定に使うmerge情報、現在のオーケストレーションのCompletion Noteを検証し、設定値、保存先、taskごとのセッション・PR対応、`completed_from_merges`、`completion_notes`を返す。Completion Noteは全オーケストレーションで共通の`completion-notes.json`に保存する。`reserved`は作成前、`child_thread_id`は作成完了を表す。状態ファイルがなければ空として扱い、それ以外の読込・対応関係の不正では失敗する。

オーケストレーションを初期化し直すときは、sessions/mergesのディレクトリだけでなく、そのIDのCompletion Noteも次で削除する。他のオーケストレーションのNoteは残す。

```text
python3 <skill-directory>/scripts/orchestration_state.py clear-completion-notes <orchestration-id>
```

## 開始するタスクを選ぶ

1. 登録済み設定からオーケストレーションIDを自動解決し、`context`で設定、セッション対応表、merge処理記録を読む。失敗したら「判断が必要」とする。
2. `task_source`から、全タスクの最新本文、直接依存、現在状態、状態履歴、優先順位を毎回読み直す。ページングと依存先を省略しない。
3. 読み直した結果を一時JSONへ正規化する。`order`にはタスク管理元の優先順位と並び順を反映する。

```json
{
  "tasks": [
    { "id": "TASK-1", "dependencies": [], "order": 0 },
    { "id": "TASK-2", "dependencies": ["TASK-1"], "order": 1 }
  ]
}
```

4. 完了タスクを次の証拠から確定する。
   - ブリッジのmerge情報
   - `context`の`completed_from_merges`
   - ブリッジ情報なしの場合、セッション対応表の`pull_request`を使った`gh pr view`の`mergedAt`とmerge commit
   - オーケストレーション開始前から完了していたことを、初回読込、状態履歴、親セッションの記録で確認できるタスク管理元の状態
5. タスク管理元だけが後から完了になったタスクは、mergeなしで完了扱いにしない。証拠が不足または矛盾する場合は「判断が必要」とする。
6. merge済みtaskにCompletion Noteがなければ、親は後続taskを開始せず、元の子セッションを再開する。`context`のsession対応から対象を特定し、同じ子セッションへmerge済みのPRを確認してCompletion Noteを保存するよう送る。すでにCompletion Noteがあれば再開しない。親はCompletion Noteを受信しても内容を表示しない。
7. `completed_from_merges`以外から確定した完了task IDだけを`--completed`で渡し、開始対象を計算する。`plan`は検証済みのmerge処理記録を自動で完了へ加えるが、merge済みの直接依存にCompletion Noteがないtaskは選ばない。`waiting_completion_notes`はその待機理由を、`dependency_completion_notes`は選ばれたtaskへ渡すべき先行taskの`handoff`と`risks`だけを返す。

```text
python3 <skill-directory>/scripts/orchestration_state.py plan <orchestration-id> \
  --tasks <normalized-tasks.json> \
  --completed <task-id> \
  --max-parallelism <user override or 4>
```

ツールが依存先の欠落、自己依存、循環、重複ID、現在のタスク管理元にない完了済み・起動済み・Note保存済みtask IDを検出した場合は「判断が必要」とする。成功時は`selected`、`waiting_dependencies`、`waiting_completion_notes`、`dependency_completion_notes`、`capacity_deferred`、`launched_uncompleted`をそのまま判断へ使う。

## 子セッションを作る

`selected`の各タスクについて、必ず一つずつ次を行う。

1. `list_projects`でrepositoryに対応する保存済みprojectを一意に特定する。
2. `context`を再実行し、task IDが未登録で、対象repositoryが`pull_request_repositories`に含まれることを確認する。含まれなければ作成せず「判断が必要」とする。`plan`の`dependency_completion_notes[task ID]`があれば、task IDごとに`handoff`と`risks`だけをGoalの参考情報として渡す。値が空の先行taskや`review_learnings`、`technical_debt`は渡さない。
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
- 先行taskのCompletion Noteから引き継ぐ`handoff`と`risks`。ない場合は参考情報を付けない

```text
python3 <skill-directory>/scripts/orchestration_state.py record-pr <orchestration-id> \
  --task-id <task-id> \
  --repository <owner/repository> \
  --number <pr-number>
```

PR本文にはオーケストレーター固有のtask IDや管理用markerを書かない。`record-pr`が失敗した場合は、PRを作り直さず、作成済みPRと失敗内容をユーザーへ返す。

## Completion Noteを保存する

merge通知を受けた親は、`context`の`completed_from_merges`と`completion_notes`を照合する。未保存のtaskだけ、session対応にある元の子セッションを再開し、次を依頼する。PR番号だけから新しい子セッションを作らない。

- merge済みのPRを確認する
- 作業で初めて分かった`risks`、`handoff`、`review_learnings`、`technical_debt`だけをJSON objectにする。該当がなければ`{}`にする
- `record-completion-note`で保存する

```text
python3 <skill-directory>/scripts/orchestration_state.py record-completion-note <orchestration-id> \
  --task-id <task-id> \
  --note-file <completion-note-json-path>
```

同じ内容の再実行は安全に扱う。保存済みのNoteと異なる内容は上書きせず停止する。保存失敗が残る間は依存taskを開始しない。

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
