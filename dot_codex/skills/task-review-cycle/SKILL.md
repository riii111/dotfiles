---
name: task-review-cycle
description: |
  `$task-worker`のローカル固定SHA差分を独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  レビュー工程の開始・再開時に使う。
---

# Task Review Cycle

初回にreview Taskを作成するときは、`model`に`gpt-6-sol`、`thinking`に`medium`を指定する。
再レビューでは`model`と`thinking`を指定せず、同じreview Taskの現在設定を維持する。
ユーザーがmodelまたはreasoning effortを明示した場合だけ、その依頼で対応する値を指定する。

## 初回手順

1. worker checkoutのrepositoryに対応するprojectと`isGitRepository`を`codex_app__list_projects`で解決する。
   Git repositoryなら`target: { type: "project", projectId: <resolved projectId>, environment: { type: "worktree" } }`を指定する。
   非Gitなら同じ`type`と`projectId`に`environment: { type: "local" }`を指定する。
   `codex_app__create_thread`を一度呼ぶ。
   親・worker Taskはforkせず、freshなproject Taskとして過去の会話を引き継がない。
   - `title`はworkerと同じ識別子で`Review <identifier>`とし、PR titleやtask titleを含めない。
   - `prompt`には下記の依頼文を使い、worker Task ID、worker checkout、候補のpush状態、review base SHA、head SHA、PR URLまたは未作成であることを渡す。
     課題・期待する挙動・制約・対象外と、その根拠となる管理元の該当節だけを事前コンテキストに含める。
     実装者の思考履歴、過去サイクル、前回のレビュー結果は含めない。
   - PR作成前の候補もローカル差分としてレビューする。
     各候補はcommit済みのhead SHAで指定する。
2. 返された`threadId`を再レビュー用に保持し、worker Taskはturnを終了する。
   初回依頼を別messageで重複送信しない。

## 再レビュー手順

1. 同じreview Taskへ`codex_app__send_message_to_thread`で`## 依頼文`を送る。
   worker Task ID、worker checkoutの絶対パス、候補のpush状態、固定したreview base SHA、最新のhead SHA、PR URLまたは未作成であることを入れる。
2. 前回の指摘は依頼文へ書かない。
3. 再レビューのたびに所定の全検証やpushを要求しない。
   worker Taskは指摘をまとめて修正し、影響する検証を行った新しいcommitを依頼する。
4. worker Taskはreview依頼を送った時点でturnを終了する。
   LGTM後は`$task-worker`の手順へ戻る。

## 依頼文

```text
$code-review
worker Task ID: <worker Task ID>
worker checkout: <worker checkoutの絶対パス>
PR: <PR URLまたは未作成（ローカル差分レビュー）>
候補状態: <未push / push済み>
review base SHA: <review base SHA>
head SHA: <head SHA>
比較範囲: <review base SHA>...<head SHA>
事前コンテキスト: <課題・期待する挙動・制約・対象外、および管理元の該当節への参照>

事前コンテキストとworker checkoutの適用規約を読んでからレビューを開始してください。
現在の比較範囲全体をレビューしてください。
Gitの読み取り、コード読取、必要な検証はworker checkoutを作業ディレクトリにして行ってください。
branchやcheckoutは変更しないでください。
worker checkoutのHEADが指定head SHAと一致することを確認してください。
PRがあり候補がpush済みなら、PR headも指定head SHAと一致することを確認してください。
不一致ならLGTMを出さずworkerへ伝えてください。
候補が未pushなら指定されたローカル差分をレビューしてください。
既存PRのheadやCIは今回候補の根拠として扱わないでください。
PRが未作成なら同じくローカル差分をレビューしてください。
変更対象にSKILLファイルがある場合は、各ファイル全体を読んで文体・用語・手順のつながりを確認してください。
重複や不要な記述、節の分け方も見直してください。
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

workerは指摘を現在のコードと規約で確かめ、妥当なものをまとめて修正する。
影響する検証後に新headをcommitし、同じreview Taskへ再レビューを依頼する。
LGTM後の全検証・通常のpush・Draft PR・CI確認は`$task-worker`の手順に従う。
検証またはCIでコードを修正した場合は、新headに影響検証と再レビューを行う。
LGTM後に所定の全検証を完了してからpushする。
push後はPR headがLGTM済みheadと一致することを確認してCI成功まで進める。
reviewerから`$task-review-cycle`で始まるmessageが届くことでworker Taskの新しいturnが始まり、workerは同じSkillを適用して指摘確認、修正、再レビューを行う。

reviewerは固定された比較範囲の実装を判定する。
base branchのtipがreview中に進んだこと自体は指摘やLGTM保留の理由にしない。
現在のbaseとの競合や意味的重複を実際に確認した場合だけ、その具体的根拠をworkerへ返す。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
