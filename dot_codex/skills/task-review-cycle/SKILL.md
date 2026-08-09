---
name: task-review-cycle
description: |
  `$task-worker`が作成したDraft PRを独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  PR作成後やレビュー工程の再開時に使う。
---

# Task Review Cycle

## 初回手順

1. worker checkoutを共有するため、worker Taskから`codex_app__fork_thread`を`same-directory`で一度呼ぶ。
2. 返された`threadId`へ`codex_app__set_thread_title`で`Review <identifier>`を設定する。
   - worker Taskと同じ`<identifier>`を使う。
   - `title`にPR titleやtask titleを含めない。
3. 同じ`threadId`へ`codex_app__send_message_to_thread`で、worker Task IDと現在のPR URL、base、head SHAを入れた`## 依頼文`を送る。
4. worker Taskはreview依頼を送った時点でturnを終了する。

## 再レビュー手順

1. 同じreview Taskへ`codex_app__send_message_to_thread`で、worker Task IDと最新のPR URL、base、head SHAを入れた`## 依頼文`を送る。
2. 前回の指摘は依頼文へ書かない。
3. worker Taskはreview依頼を送った時点でturnを終了する。

## 依頼文

```text
$code-review
worker Task ID: <worker Task ID>
PR: <PR URL>
比較範囲: <base>...<head SHA>

現在の比較範囲全体をレビューしてください。
再レビューでも前回の指摘だけに限定せず、新しい問題がないか確認してください。
PRへの投稿、修正、Ready化、mergeは行わないでください。
```

worker Taskへ返すmessageは次の形式にしてください。

```text
$task-review-cycle

<レビュー結果>
```

この`$task-review-cycle`はworker Taskへのmessageの先頭に置く文字列であり、reviewerは適用しません。
reviewerは`$code-review`でレビューします。

レビュー完了後、`codex_app__send_message_to_thread`の`threadId`にworker Task IDを指定して結果を返してください。
送信が受理されたことを確認したらreviewerのturnを終了してください。

## 制約

workerは指摘を現在のコードと規約で確かめ、妥当なものを修正する。
所定の全検証、commit、pushの後に再レビューを依頼し、LGTMまで反復する。
reviewerから`$task-review-cycle`で始まるmessageが届くことでworker Taskの新しいturnが始まり、workerは同じSkillを適用して指摘確認、修正、再レビューを行う。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
