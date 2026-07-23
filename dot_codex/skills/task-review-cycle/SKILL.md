---
name: task-review-cycle
description: |
  task-workerが作成したDraft PRのreview side chat、指摘修正、再レビュー、検証、manualまたはautoの完了処理を担当する。task-workerからPR作成後の制御を引き継ぐとき、または停止したレビュー工程を再開するときに使う。
---

# Task Review Cycle

PR作成後からmergeまでを担当する。実装開始前の作業とCompletion Note生成は扱わない。

## 状態から再開する

PRのstate、draft、head SHA、checksと、状態にあるreview thread ID、待機中turn ID、review結果を読み直す。ここで`checks`は最新headに対するrepository所定のローカル全検証とGitHub必須status checksをまとめた合否状態を指す。PRの実状態がmergedまたはclosedなら、`next`より先に対応するeventを適用する。`manual`は明示されない限り既定値とし、過去の慣例から`auto`を推測しない。

オーケストレーションID、task ID、task管理元、child thread ID、repository、base、完了方針が揃っていることを確認する。不足値は`orchestration_state.py context`から取得し、推測しない。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py next <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id>
```

返された操作を一つだけ実行する。出力の`allowed_events`がevent名と必須fieldを示す。操作後は結果をJSON fileへ書き、次を実行する。状態を手編集せず、PR状態や合格条件を別の節で再判定しない。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py apply-event <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --event-file <event-json-path>
```

- `request_review`: review side chatを一度だけ作り、レビューを依頼する。
- `wait_review`: 同じreview turnの完了を待つ。timeout中は依頼を重ねない。
- `address_review`: 指摘を差分とrepository realityで確認し、妥当なものを修正、全検証、commit、pushする。修正後headを状態へ保存する。指摘件数は直前の`review_completed`を維持し、再レビューの要否は状態遷移スクリプトに再照会する。
- `verify`: 最新headの全検証と必須checksを確認する。
- `wait_checks`: checksの完了を待つ。
- `stop_checks_failed`: 自動再試行せず、失敗内容を報告してユーザー判断を待つ。再試行の指示があれば`checks_retry_requested` eventを適用する。
- `report_manual`: Draftのままreview結果と検証結果を報告して止まる。
- `mark_ready`: `auto`の明示許可を確認してReady for reviewへ変更する。
- `merge`: 最新headと必須checksを再確認してmergeする。
- `record_completion_note`または`complete`: `completion-report`へ引き継ぐ。
- `stop_conflict`: PRを変更せず、競合状態を報告して停止する。
- `stop_closed`: PRを変更せず、closed状態を報告して停止する。
- `stop_policy_mismatch`: PRをDraftへ戻さず、現在状態と完了方針の不一致を報告して停止する。

ユーザーが完了方針を変更したら`policy_changed` eventを適用する。`report_manual`後にユーザーがこの子セッションへmergeを直接依頼した場合は、そのtaskへの明示的な`auto`許可として`policy_changed` eventを適用し、`next`から再開する。merge後は`completion-report`まで続け、親への完了通知を確認する。review確定後にユーザー指示でcommitが追加されたら`head_changed` eventを適用し、reviewとchecksを新しいheadでやり直す。review結果を待つ間もユーザーの最新指示へ応答する。

## review side chat

現在の子セッションをsame-directoryで一度だけforkし、`[Review] <task-id>: <PR title>`にする。状態にthread IDがあれば再利用する。IDがなく既存chatの可能性があれば`list_threads`と`read_thread`で同じtask IDとPRを探す。一意に確認できなければ重複作成せずユーザーへ確認する。

初回と再レビューは`gpt-5.6-sol`、`high`で次を逐語的な依頼の基礎にする。結果の`Blocking`と`Non-blocking`をそれぞれ数え、`review_completed` eventへ渡す。

```text
$code-reviewを使い、<owner/repository>のPR #<number>をbase <base>との差分でsingle reviewしてください。
担当はtask <task-id>、タスク管理元は<task-source>です。最新のタスク本文と依存タスクを再読してください。
repository規約、タスク資料、呼び出し元やテストを確認し、code-review SKILLの形式で指摘を出し切ってください。
指摘がなければLGTMとしてください。
結果の先頭に`Reviewed head: <head SHA>`を付けてください。
結果は必ず`send_message_to_thread`で子セッション <child-thread-id> へ送ってください。
PRへのコメント投稿、修正、mergeは行わないでください。
```

`wait_review`では保存済みturn IDを対象に`wait_threads`で待つ。`wait_threads`が`timed_out`を返した状態をtimeoutとし、失敗ではなく同じturnを待機中として停止する。timeout中は再開依頼やreview依頼を重ねない。

review対象headから追加commitがある結果、通知失敗、意図しないbase、`manual`でReadyになっている状態は自動復旧せず停止する。競合は`mergeability_changed` eventで状態へ反映し、`stop_conflict`として停止する。
