---
name: task-review-cycle
description: |
  `$task-worker`が作成したDraft PRを独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  PR作成後やレビュー工程の再開時に使う。
---

# Task Review Cycle

初回にreview Taskを作成するときは、`model`に`gpt-5.6-sol`、`thinking`に`medium`を指定する。
再レビューでは`model`と`thinking`を指定せず、同じreview Taskの現在設定を維持する。
ユーザーがmodelまたはreasoning effortを明示した場合だけ、その依頼で対応する値を指定する。

## 初回手順

1. worker Taskから`codex_app__create_thread`を`target: { type: "projectless" }`で一度呼ぶ。親・worker Taskはforkせず、過去の会話を引き継がない。
   - `title`はworkerと同じ識別子で`Review <identifier>`とし、PR titleやtask titleを含めない。
   - `prompt`は下記の`## 依頼文`とし、課題・期待する挙動・制約・対象外と、その根拠となる管理元の該当節だけを事前コンテキストに含める。実装者の思考履歴、過去サイクル、前回のレビュー結果は含めない。
2. 返された`threadId`を再レビュー用に保持し、worker Taskはturnを終了する。初回依頼を別messageで重複送信しない。

## 再レビュー手順

1. 同じreview Taskへ`codex_app__send_message_to_thread`で、worker Task ID、worker checkoutの絶対パス、最新のPR URL、固定したreview base SHA、head SHAを入れた`## 依頼文`を送る。
2. 前回の指摘は依頼文へ書かない。
3. worker Taskはreview依頼を送った時点でturnを終了する。

## 依頼文

```text
$code-review
worker Task ID: <worker Task ID>
worker checkout: <worker checkoutの絶対パス>
PR: <PR URL>
比較範囲: <review base SHA>...<head SHA>
事前コンテキスト: <課題・期待する挙動・制約・対象外、および管理元の該当節への参照>

事前コンテキストとworker checkoutの適用規約を読んでからレビューを開始してください。
現在の比較範囲全体をレビューしてください。
Gitの読み取り、コード読取、必要な検証はworker checkoutを作業ディレクトリにして行ってください。branchやcheckoutは変更しないでください。
再レビューでも前回の指摘だけに限定せず、新しい問題がないか確認してください。
review開始後にbase branchが進んでも、それだけを理由にLGTMを保留しないでください。
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

reviewerは固定された比較範囲の実装を判定する。
base branchのtipがreview中に進んだこと自体は指摘やLGTM保留の理由にしない。
現在のbaseとの競合や意味的重複を実際に確認した場合だけ、その具体的根拠をworkerへ返す。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
