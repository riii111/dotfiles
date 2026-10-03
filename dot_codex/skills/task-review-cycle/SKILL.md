---
name: task-review-cycle
description: |
  `$task-worker`のローカル固定SHA差分を独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  レビュー工程の開始・再開時に使う。
---

# Task Review Cycle

commit済み候補をfreshなCodex reviewerで独立レビューし、Blockingが解消されるまで同じreview Taskで修正・再レビューを続ける。Non-blockingは任意とする。
review baseは[task-worker](../task-worker/SKILL.md)に従って固定し、LGTM後も同じheadで最終検証・Draft PR・CI確認を行う。

## 依頼の準備と送信

[依頼JSON](references/request.md)を作り、`reviewctl prepare --request <JSONファイル>`を実行する。CLIは候補SHAを検証してtool名とargumentsを返す。APIは呼ばず、送信と結果の受取には既存ツールを使う。CLI未導入時は[直接ツールの手順](references/direct-tools.md)に従う。

| worker | 送信ツール | 結果の受取 |
| --- | --- | --- |
| Codex | `codex_app__create_thread` / `codex_app__send_message_to_thread` | reviewerの返信で次turnを開始 |
| Claude | harnexusの`create_thread` / `send_message_to_thread` | `wait_threads` / `read_thread` |

1. 出力されたtoolのargumentsを対応するツールへ渡す。初回はfreshなreview Taskを作り、再レビューは同じreviewerを使う。モデルの既定は`gpt-6.1-sol`・`medium`。再レビューは現在の設定を維持し、ユーザーが変更を明示した場合だけ`--model`・`--thinking`を渡す。
2. 送信の受理と確定したthreadIdを確認し、`reviewctl record --request <JSONファイル> --reviewer-thread-id <確定ID>`で保存する。Codex workerはturnを終了する。Claude workerは下記の受取を続ける。
3. 回答の比較範囲が依頼したbase/headと一致することを確認する。Blockingをまとめて修正・影響検証・commitし、JSONのheadを更新してprepareから再レビューする。判定保留なら不足を解消する。

Claude workerは`wait_threads`へreviewer IDを渡し、timeoutMsを60000以下にする。cursorは次回のafterCursorへ渡す。正常timeoutでは待機を続け、対象別errorsや失敗・中断は理由を確認する。完了時の回答が足りなければ`read_thread`で読み、commentaryだけで判定しない。workerへの返信は要求しない。

## 制約

projectIdは既存のlist_projectsでrepositoryとisGitRepositoryを確認して選ぶ。CLI経路はGit worktreeのレビューに使う。
送信結果が不明な場合やclientThreadIdだけが返された場合はAppの状態を確認し、同じ依頼を再送しない。確定IDが分かるまでrecordしない。
Claude workerのreviewerはCodexモデルに限られる。Claudeモデルを指定された場合は制約を伝え、対応するモデルの指定を求める。
reviewerには課題・期待する挙動・制約・対象外と管理元の該当節を渡し、実装者の思考履歴・過去サイクル・前回の指摘は含めない。
再開時は`reviewctl state`と既存review Taskを確認して続ける。明示許可なしにReady化やmergeを行わない。
