---
name: task-review-cycle
description: |
  task-workerが作成したDraft PRを独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。PR作成後やレビュー工程の再開時に使う。
---

# Task Review Cycle

worker checkoutを共有するため、Draft PRのreview Taskをworker Taskからsame-directoryで一度forkし、`[Review] <task-id>: <PR title>`にする。
再開時は同じtitleのreview Taskを再利用する。
`$code-review`を使ってbaseとの差分をレビューするよう依頼する。
PRへの投稿、修正、Ready化、mergeはreviewerにさせない。

review依頼にはworker Task IDとreview対象headを含める。
reviewerは`send_message_to_thread`でworker Taskへ結果を返す。
再レビューは新しいTaskを作らず同じreview Taskへ依頼し、毎回、最新headのbase差分全体を先入観なく確認する。
再レビュー依頼では前回の指摘を詳しく説明しない。

workerは指摘を現在のコードと規約で確かめ、妥当なものを修正する。
所定の全検証、commit、pushの後に再レビューを依頼し、LGTMまで反復する。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
