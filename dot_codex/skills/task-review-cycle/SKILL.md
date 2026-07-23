---
name: task-review-cycle
description: |
  task-workerが作成したDraft PRのreview side chat、指摘修正、再レビュー、検証、manualまたはautoの完了処理を担当する。
---

# Task Review Cycle

PR作成後からmergeまでを担当する。実装開始前の作業とCompletion Note生成は扱わない。

## 状態から再開する

PRのstate、draft、head SHA、checksと、現在headに対するreview結果を読み直す。`manual`は明示されない限り既定値とし、過去の慣例から`auto`を推測しない。

`task-worker/scripts/worker_transition.py`へ最新状態を渡し、返された操作を一つだけ実行する。操作後は外部状態を再読してスクリプトを再実行する。PR状態や合格条件を別の節で再判定しない。

- `request_review`: review side chatを一度だけ作り、レビューを依頼する。
- `wait_review`: 同じreview turnの完了を待つ。timeout中は依頼を重ねない。
- `address_review`: 指摘を差分とrepository realityで確認し、妥当なものを修正、全検証、commit、pushする。BlockingがなくNon-blockingが2件以内なら`review: passed`、それ以外は同じside chatへ再レビューを依頼して`review: pending`にする。
- `verify`: 最新headの全検証と必須checksを確認する。
- `wait_checks`: checksの完了を待つ。
- `report_manual`: Draftのままreview結果と検証結果を報告して止まる。
- `mark_ready`: `auto`の明示許可を確認してReady for reviewへ変更する。
- `merge`: 最新headと必須checksを再確認してmergeする。
- `record_completion_note`または`complete`: `completion-report`へ引き継ぐ。

## review side chat

現在の子セッションをsame-directoryで一度だけforkし、`[Review] <task-id>: <PR title>`にする。既存IDは再利用する。存在が不明なら重複作成しない。

初回と再レビューは`gpt-5.6-sol`、`high`で、`code-review`を使ってbaseとの差分全体を確認させる。結果の先頭に`Reviewed head: <head SHA>`を付け、現在の子セッションへ送らせる。PRへの投稿、修正、mergeはさせない。

review対象headから追加commitがある結果、通知失敗、競合、意図しないbase、`manual`でReadyになっている状態は自動復旧せず停止する。
