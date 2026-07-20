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

セッション対応表とmerge処理記録は、絶対パスの`XDG_STATE_HOME`または`$HOME/.local/state`配下から読む。

```text
codex-task-orchestrator/<orchestration-id>/sessions.json
```

```json
{
  "version": 3,
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

`pull_request`はdraft PR作成後に追加する。子セッションの作成前または作成待ちでは、task entryをそれぞれ次の形にする。

```json
{"creation": {"status": "reserved"}}
{"creation": {"status": "pending", "client_thread_id": "client-thread-id"}}
```

タスク本文、タスク管理元の状態、依存関係は保存しない。version 1と2は読込時に受け入れ、次の書込でversion 3へ更新する。

merge処理記録は参照だけにする。通知状態の条件は以下。

- `parent_notification`: `pending`または`delivered`
- `local_notification`: `not_sent`または`sent`
- ファイルなし: 未処理記録なしとして扱う
- JSON、version、必須値が不正: 修復せず「判断が必要」とする

`context`はmerge処理記録をschema検証し、セッション対応表のtask ID・repository・PR番号と一致する記録だけを`completed_from_merges`として返す。不一致、重複task ID、不正な通知状態では失敗する。

## 開始するタスクを選ぶ

1. `context`で設定、セッション対応表、merge処理記録を読む。失敗したら「判断が必要」とする。
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
6. `completed_from_merges`以外から確定した完了task IDだけを`--completed`で渡し、開始対象を計算する。`plan`は検証済みのmerge処理記録を自動で完了へ加える。

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
3. `create_thread`より先に作成予約を保存する。

```text
python3 <skill-directory>/scripts/orchestration_state.py reserve-session <orchestration-id> \
  --task-id <task-id>
```

4. `create_thread`を一回だけ呼ぶ。project targetの`environment`は必ず`local`とし、promptには下記Goalを使う。通常のlocal作成は`threadId`と`hostId`を直接返す。`clientThreadId`を返すCodex管理worktreeは指定しない。
5. `threadId`を取得した直後に保存する。

```text
python3 <skill-directory>/scripts/orchestration_state.py record-session <orchestration-id> \
  --task-id <task-id> \
  --child-thread-id <thread-id>
```

6. 禁止したworktree作成を指定していないにもかかわらず`clientThreadId`だけ返った場合は、直ちにpendingとして保存し、それ以上作成せず「判断が必要」とする。

```text
python3 <skill-directory>/scripts/orchestration_state.py record-pending <orchestration-id> \
  --task-id <task-id> \
  --client-thread-id <client-thread-id>
```

7. 保存後に`set_thread_title`で`[<task-id>] <task title>`へ変更する。

予約後の作成失敗、pending、ID保存、タイトル変更の失敗では予約を消さず、同じタスクを再作成しない。保存済みの状態と失敗内容を返す。

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
- セッションの予約、作成、ローカル状態への保存を確認できない

## 結果

作成したtask・タイトル・thread ID、予約またはpendingのtask、完了taskと根拠、見送ったtaskと理由、依存待ちtaskと未完了依存、対応表の保存先を返す。作成対象がない確定状態は`開始可能なタスクなし`とする。
