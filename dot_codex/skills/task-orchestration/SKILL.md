---
name: task-orchestration
description: |
  オーケストレーションIDに紐づくタスク群を毎回読み直し、PRのmergeと依存関係から次に開始できるタスクを選び、通常の独立したCodex子セッションを重複なく作成する。
  最初のタスク開始、merge通知後の再開、開始済み・依存待ちタスクの整理に使う。
---

# Task Orchestration

一回の実行で、次に同時開始するタスクを選ぶ。subagent、`fork_thread`、Codex管理のworktreeは使わない。

## 入力値

入力値は以下。

- オーケストレーションID: 必須。`codex-task-orchestrator init`で登録したID
- base: 必須
- 最大並列数: 必須。正の整数
- ブリッジから受け取ったmerge情報: 任意
- 子セッション用SKILL: 任意。既定は「利用なし」
- merge方針: 任意。既定は「手動merge」

必須値を過去の会話からも確定できなければ、既定branchや並列数を推測せず「判断が必要」として返す。

## 状態管理ツール

`scripts/orchestration_state.py`を、設定とセッション対応表の読込、schema検証、開始対象の計算、ID保存に使う。これらをAIの手作業で再実装しない。

設定確認:

```text
python3 <skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

ツールは、絶対パスの`XDG_CONFIG_HOME`または`$HOME/.config`からRust実装と同じ設定schemaを読む。

```toml
[orchestrations.<orchestration-id>]
parent_thread_id = "parent-thread-id"
repository = "owner/repository"
task_source = "task-source"
```

セッション対応表は、絶対パスの`XDG_STATE_HOME`または`$HOME/.local/state`配下に保存する。

```text
codex-task-orchestrator/<orchestration-id>/sessions.json
```

```json
{
  "version": 2,
  "parent_thread_id": "parent-thread-id",
  "tasks": {
    "TASK-1": {
      "child_thread_id": "child-thread-id",
      "pull_request": {
        "repository": "owner/repository",
        "number": 123
      }
    }
  }
}
```

`pull_request`はdraft PR作成後に追加する。タスク本文、状態、依存関係は保存しない。version 1は読込時に受け入れ、次の書込でversion 2へ更新する。

merge処理記録は参照だけにする。通知状態の条件は以下。

- `parent_notification`: `pending`または`delivered`
- `local_notification`: `not_sent`または`sent`
- ファイルなし: 未処理記録なしとして扱う
- JSON、version、必須値が不正: 修復せず「判断が必要」とする

## 開始するタスクを選ぶ

1. `context`で設定とセッション対応表を読む。失敗したら「判断が必要」とする。
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
   - `merges.json`のtask IDとmerge commit
   - ブリッジ情報なしの場合、セッション対応表の`pull_request`を使った`gh pr view`の`mergedAt`とmerge commit
   - オーケストレーション開始前から完了していたことを、初回読込、状態履歴、親セッションの記録で確認できるタスク管理元の状態
5. タスク管理元だけが後から完了になったタスクは、mergeなしで完了扱いにしない。証拠が不足または矛盾する場合は「判断が必要」とする。
6. 完了task IDを`--completed`で渡し、開始対象を計算する。

```text
python3 <skill-directory>/scripts/orchestration_state.py plan <orchestration-id> \
  --tasks <normalized-tasks.json> \
  --completed <task-id> \
  --max-parallelism <count>
```

ツールが依存先の欠落、自己依存、循環、重複ID、現在のタスク管理元にない完了済み・起動済みtask IDを検出した場合は「判断が必要」とする。成功時は`selected`、`waiting_dependencies`、`capacity_deferred`、`launched_uncompleted`をそのまま判断へ使う。

## 子セッションを作る

`selected`の各タスクについて、必ず一つずつ次を行う。

1. `list_projects`でrepositoryに対応する保存済みprojectを一意に特定する。
2. `context`を再実行し、task IDが未登録であることを確認する。
3. `create_thread`を一回だけ呼ぶ。project targetの`environment`は`local`とし、promptには下記Goalを使う。
4. `threadId`を得る。`clientThreadId`しかなければ、文書化済みの作成待機手段で対応する`threadId`を待つ。
5. thread IDを取得した直後に保存する。

```text
python3 <skill-directory>/scripts/orchestration_state.py record-session <orchestration-id> \
  --task-id <task-id> \
  --child-thread-id <thread-id>
```

6. 保存後に`set_thread_title`で`[<task-id>] <task title>`へ変更する。

作成待機、ID保存、タイトル変更の失敗では同じタスクを再作成せず、作成済みIDと失敗内容を返す。

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
- 手動merge、または明示的に許可された条件付き自動merge

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
- セッション作成、作成待機、ローカル状態への保存を確認できない

## 入力例

通常の開始:

```text
$task-orchestrationを使って、次に開始できるタスクを選んでください。
オーケストレーションID: example-project
base: origin/main
最大並列数: 3
子セッション用SKILL: 利用なし
merge方針: 手動merge
```

入力不足:

```text
$task-orchestrationを使って、example-projectのタスクを開始してください。
```

後者では不足項目を示し、子セッションを作らない。

## 結果と検証

作成したtask・タイトル・thread ID、完了taskと根拠、見送ったtaskと理由、依存待ちtaskと未完了依存、対応表の保存先を返す。作成対象がない確定状態は`開始可能なタスクなし`とする。

実threadを作らない検証では`tests/test_orchestration_state.py`を実行し、次を確認する。

- 独立したA・Bを同時に選び、両方の完了後にCを選ぶ
- 未完了の起動済みタスクが並列数を消費する
- 欠落した依存先を拒否する
- セッション登録が冪等で、異なるthread IDへの上書きを拒否する
- version 1を読み、PR番号の記録時にversion 2へ更新する
- PR本文へ管理用markerを要求しない
