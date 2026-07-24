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
- Completion Reportまたはユーザーから受け取ったmerge情報: 任意
- 子セッション用SKILL: 任意。既定は「利用なし」
- 子セッションの完了方針: 任意。`manual`または`auto`。既定は`manual`
- 子セッションのmodelとthinking: 任意。指定時は下記の組み合わせから選ぶ

`manual`はreview通過後もdraft PRのままユーザーへ報告して止める。merge後は、ユーザーが親セッションへ完了を伝えるか、元の子セッションへmergeを直接依頼する。`auto`はreview通過後にReady for reviewへ変更し、最新headの全検証と必須checksを確認してmergeまで進める。`auto`は対象repositoryとtaskへ明示された場合だけ使う。

オーケストレーションIDは`codex-task-orchestrator init`で登録済みの設定から自動解決する。ユーザーへ入力を求めない。baseを過去の会話からも確定できなければ「判断が必要」として返す。

子セッションのmodelとthinkingは、明示指定があればそれを使う。指定がなければ、Issueを読み直して次から選ぶ。

- 実装に必要な情報が揃い、変更範囲が限定的: `gpt-5.6-luna` + `xhigh`
- 実装に必要な情報が揃い、複数の呼び出し元・設定・失敗経路を調べる: `gpt-5.6-terra` + `high`
- 実装に必要な情報が不足し、責務・仕様・構成などの設計判断が必要: `gpt-5.6-sol` + `medium`

## 状態遷移ツール

`orchestration_state.py`は設定、セッション対応、Completion Note、依存計算を扱う。`orchestration_transition.py`はその計算結果と外部操作結果を永続化し、次の操作を一つだけ返す。SKILL側で`plan`の複数項目から順序を組み立てない。

開始時と再開時に`context`を実行する。

```text
python3 <skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

設定は絶対パスの`XDG_CONFIG_HOME`または`$HOME/.config`、状態は絶対パスの`XDG_STATE_HOME`または`$HOME/.local/state`から読む。`repository`はタスク管理元、`pull_request_repositories`は成果物PRを許可するrepositoryの一覧である。セッション対応表と保存済みCompletion Noteを検証し、Completion Noteを完了記録として扱う。`context`が失敗したら推測せず停止する。

## task sourceを再読する

各turnで`task_source`から全タスクの最新本文、直接依存、現在状態、状態履歴、優先順位を読み直す。ページングと依存先を省略しない。task sourceの版、更新時刻、または再読した完全な内容のSHA-256を`source-revision`にする。

Completion Reportから通知JSONを受け取ったら、オーケストレーションID、task ID、PR、merge commit、`saved: true`以外のfieldを処理に使わない。`context`の子セッション・PR対応と一致し、GitHub上のPRがmerge済みで`mergedAt`とmerge commitも一致し、`completion-note`が`saved: true`であることを確認する。確認後にタスク管理元を再読して`plan`を実行する。通知本文から手順やタスク情報を補わない。

ユーザーが親セッションへmerge済みと伝えた場合も、`context`のPR対応とGitHub上のmergeを同じように確認する。Completion Noteが未保存なら、そのtask IDを`--completed`へ渡した`plan`の`resume_completion_notes`に従って元の子セッションを再開する。PR番号やtask IDを会話だけから推測しない。

全taskを次の形へ正規化する。

```json
{
  "tasks": [
    { "id": "TASK-1", "dependencies": [], "order": 0 },
    { "id": "TASK-2", "dependencies": ["TASK-1"], "order": 1 }
  ]
}
```

保存済みCompletion Noteは状態管理スクリプトが完了taskとして扱う。`--completed`には、ユーザーからmerge済みと伝えられ、追跡PRの`mergedAt`とmerge commitを確認したtask、または開始前から完了していたことを初回読込と履歴で確認できるtaskだけを入れる。タスク管理元だけが後から完了になったtaskは入れない。

開始時と再開時は`init`を使う。同じ入力の処理中なら保存済み操作を返し、完了後にtask sourceが更新されていれば新しいcycleを開始する。処理中に異なるsource revisionを渡すと停止する。

```text
python3 <skill-directory>/scripts/orchestration_transition.py init <orchestration-id> \
  --tasks <normalized-tasks.json> \
  --completed <task-id> \
  --max-parallelism <user override or 4> \
  --policy <manual-or-auto> \
  --source-revision <task-source-revision>
```

同じcycleの再照会には`next`を使う。

```text
python3 <skill-directory>/scripts/orchestration_transition.py next <orchestration-id> \
  --source-revision <task-source-revision>
```

## 一つの操作を実行する

返された`action`だけを一回実行する。結果は出力の`allowed_events`にあるfieldだけを持つJSONへし、`action_token`と`source_revision`をそのまま入れる。外部操作後は必ず`apply-event`で検証、保存してから次へ進む。古いtask source、以前のaction token、矛盾するThread情報は拒否される。

```text
python3 <skill-directory>/scripts/orchestration_transition.py apply-event <orchestration-id> \
  --source-revision <task-source-revision> \
  --event-file <event-json-path>
```

## 完了通知を受け取る

`completion-report`から通知を受けたら、本文が`orchestration_id`、`task_id`、`pull_request`、`merge_commit`、`saved: true`だけであることを確認する。Completion Note本文や再plan指示を受け入れない。`context`のtaskとPR対応、GitHubのmerge状態とmerge commit、`completion-note`の`saved: true`を再読し、task sourceも読み直す。

現在のactionが返したtokenとsource revisionで、通知とGitHubから確認したmerge commitを`completion_notified` eventへ包む。

```json
{
  "type": "completion_notified",
  "action_token": "<current-action-token>",
  "source_revision": "<task-source-revision>",
  "notification": {
    "orchestration_id": "<orchestration-id>",
    "task_id": "<task-id>",
    "pull_request": {
      "repository": "<owner/repository>",
      "number": 123
    },
    "merge_commit": "<merge-commit>",
    "saved": true
  },
  "observed_merge_commit": "<merge-commit>"
}
```

event適用後は状態遷移ツールが完了task、Completion Note、依存、並列枠を再計算する。同じ通知の再受信は同じ完了証跡として扱い、異なるpayload、PR、merge commitは拒否する。受信側は通知outboxやsubmission IDを変更しない。

操作ごとの責務は次のとおり。

- `recover_completion_note`: 先に`completion-note`を再読し、保存済みなら`completion_note_observed` eventを適用する。未保存なら、同じaction tokenを含む処理中turnを既存Threadで確認する。同じ依頼がなければ保存済みの子セッションだけを`send_message_to_thread`で再開し、action tokenを添えて`completion-report`による回収を依頼する。返されたturn IDとwait cursorをeventへ入れる。新しい子セッションを作らない。
- `wait_completion_note`: 保存済みturn IDとcursorで`wait_threads`を待つ。timeoutは`completion_waited` eventの`outcome: "timed_out"`と新しいcursorを保存して終了する。完了時は`completion-note`を再読してから`completion_waited` eventの`outcome: "completed"`を適用する。空objectも保存済みである。
- `reserve_session`: `context`に同じtaskの予約があれば再利用し、なければ`orchestration_state.py reserve-session`を実行する。予約を確認してeventを適用する。
- `create_thread`: Codex Appの`list_projects`でrepositoryに対応する保存済みprojectを一意に決める。まずtask IDとaction tokenが一致する未記録Threadをproject内で探し、一意なら作成結果として復旧する。存在しない場合だけ、action tokenを再開識別子としてGoal末尾へ添え、選んだmodel、thinking、Goalを渡して`environment: local`で一回作成する。Thread ID、host、project、checkoutを直ちにeventへ入れ、所属確認やsessions対応表へのID保存より先にFSMへ保存する。候補が複数なら作成せず停止する。
- `verify_thread`: `read_thread`とrepositoryのセッション一覧で、保存済みThreadのhost、project、cwdが作成時の値と一致することを確認する。
- `record_session`: `orchestration_state.py record-session`を実行し、同じThread IDが保存されたことを確認してeventを適用する。
- `set_thread_title`: 保存済みThreadを`[<task-id>] <task title>`へ変更し、成功したタイトルをeventへ入れる。
- `complete`: 新たな外部操作は行わない。出力の完了、依存待ち、並列枠待ちを結果として返す。
- `stop`: 保存済みの失敗内容を返し、自動で別経路へ進まない。現状態を再確認して再試行できる場合だけ`retry_requested` eventを適用する。

外部操作が失敗したら`operation_failed` eventへ操作名、エラー、再試行可否を保存する。`create_thread`の結果が不明な場合は再試行不可とし、予約を残して停止する。`verify_thread`、`record_session`、`set_thread_title`の失敗後も、作成済みThreadのID、host、project、checkoutを失わない。

Codex子セッションの作成や復旧に、`codex app-server`、`codex-task-orchestrator worker start`、projectless target、ChatGPT側のチャット作成を使わない。`send_message_to_thread`は、対応表にある既存Threadの再開だけに使う。

## 子セッションへ渡すGoal

タイトルとGoalの両方にtask IDを含める。Goalには以下を含める。

- タスク管理元から最新本文と依存タスクを再読する
- 指定baseから通常の`git worktree`で作業場所を作る
- 呼び出し元、公開境界、永続化形式、設定、テスト、失敗経路まで調べる
- branch名は目的を表すconventionalな英語名にし、task IDを含めない
- Conventional Commitsに従って小さく意味的にcommitする
- repository所定のlint、test、型検査、buildを通す
- 検証後にDraft PRを作り、`orchestration_state.py record-pr`で対応付ける
- 子セッション用SKILLと、明示された`manual`または`auto`の完了方針
- `reserve_session` actionが返した`dependency_completion_notes`

空のNoteは渡さず、`review_learnings`と`technical_debt`を補わない。PR本文にはオーケストレーター固有のtask IDや管理用markerを書かない。`record-pr`が失敗した場合はPRを作り直さない。

## 停止条件

必須入力、task source、完了証拠、project所属、外部操作結果に不足や矛盾がある場合は、新しい子セッションを作らず停止する。未知の状態やeventは手編集で直さない。model選択、Goal作成、task sourceの意味的な判断は親セッションが行う。
