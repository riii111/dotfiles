---
name: task-review-cycle
description: |
  `$task-worker`のローカル固定SHA差分を独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  レビュー工程の開始・再開時に使う。
---

# Task Review Cycle

commit済み候補をfreshなCodex reviewerで独立レビューし、Blockingが解消されるまで同じreview Taskで修正・再レビューを続ける。Non-blockingは任意とする。
review baseは[task-worker](../task-worker/SKILL.md)に従って固定し、LGTM後も同じheadで最終検証・Draft PR・CI確認を行う。

## CLIでのレビュー

`reviewctl doctor`が成功した場合は以下を使う。App接続機能が未導入なら[直接ツールを使う手順](references/direct-tools.md)に従う。

1. [依頼JSON](references/request.md)を作り、`reviewctl start --request <JSONファイル>`を実行する。
   初回reviewerは既定で`gpt-6.1-sol`・`medium`。ユーザーが指定した値は`--model`・`--thinking`で渡す。
2. `reviewctl wait`を実行し、未完了なら再度待つ。返却された比較範囲が依頼したbase/headと一致することを確認する。
3. Blockingをまとめて修正し、影響検証とcommitを行う。依頼JSONのheadを更新して`reviewctl rerun --request <JSONファイル>`を実行し、再度待つ。
   再レビューでは同じreviewerと現在のモデル設定を維持する。ユーザーが変更を明示した場合だけ`--model`・`--thinking`を渡す。
4. LGTMならtask-workerの最終検証へ戻る。判定保留なら不足を解消し、同じreviewerで続ける。

CLIはレビュー依頼の生成・送信・結果読取・review TaskのID保存を行う。Claude/CodexともCLI経路ではreviewerの最終回答を取得し、workerへの返信を要求しない。
保存された書込結果が不明な場合は、CLIの指示に従ってAppを確認する。直接ツールへ切り替えて同じ依頼を再送しない。

## 制約

reviewerには課題・期待する挙動・制約・対象外と管理元の該当節を渡し、実装者の思考履歴・過去サイクル・前回の指摘は依頼文へ含めない。
再開時は既存のreview Taskと候補SHAを確認して続ける。明示許可なしにReady化やmergeを行わない。
