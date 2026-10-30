---
name: task-review-cycle
description: |
  `$task-worker`のローカル固定SHA差分を独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  レビュー工程の開始・再開時に使う。
---

# Task Review Cycle

commit済み候補をfreshなCodex reviewerへ渡し、以後は同じreview Taskで続ける。
修正・検証・review基点・完了条件は[task-worker](../task-worker/SKILL.md)に従う。
LGTMの後に、owner・レビュアー・reviewerから伝えられた指摘への修正は、再レビューに回さない。
対象の範囲と完了条件は、task-workerの「PRへの指摘対応」に従う。

## 依頼と結果の受取

`harnexus-task`が未導入ならユーザーに伝えて停止する。
worktreeに`*`だけの`.gitignore`を置いた`.reviewctl/`を作り、[依頼JSON](references/request.md)を`.reviewctl/request.json`へ保存する。
候補はcommit済みで、追跡ファイルに未commitの変更がないことを`git status`で確認する。

1. `harnexus-task review --request <worktree>/.reviewctl/request.json`をサンドボックス外で一度実行する。
   Codexは`sandbox_permissions: require_escalated`を付け、Claudeはそのまま実行する（サンドボックス対象外）。
   パイプ・リダイレクト・`cd`などを付けず単独で実行する（付けると対象外にならない）。
   ユーザーがモデル設定を指定した場合だけ`--model`・`--thinking`を渡す。
2. harnexus-taskがbase/head SHAを固定し、初回はreviewerを作成、以後は同じreviewerへ送る。
   同じheadは再送しない。
   失敗時は出力の理由を報告し、create_thread・send_message_to_threadを直接呼ばない。
3. 結果を受け取る。
   Codexはturnを終了し、reviewerの返信で次turnを始める。
   Claudeはharnexusの`wait_threads` / `read_thread`で待つ。
4. 最終回答のbase/headが`harnexus-task state --request <JSON>`の`base`・`head`と一致することを確認する。
   修正後は同じJSONのPR URL・参照文書を必要に応じて更新し、手順1から繰り返す。
   LGTM後の指摘への修正では繰り返さない。
   判定保留なら不足を解消する。

Claudeはwait_threadsのtimeoutMsを60000以下にし、cursorを次のafterCursorへ渡す。
正常timeoutでは待機を続け、対象別errors・失敗・中断は理由を確認する。
最終回答が足りなければread_threadで最新1turn・出力なしから読み、commentaryだけで判定しない。
Claude workerのreviewerはCodexモデルに限られる。
Claudeモデルを指定された場合は、対応するモデルの指定を求める。

結果不明・モデル不一致では再実行しても送信されない。
ユーザーがAppで確認した結果だけを、承認を得て記録する。
送信済みなら`harnexus-task resolve --request <JSON> --sent [--thread-id <ID>]`、未送信なら`--not-sent`で記録する。

## 再開と基点更新

`harnexus-task state --request <JSON>`の出力は平らなJSONで、次のキーを最上位から読む。

- `reviewerThreadId`
- `base`・`head`
- `prompt`：最後に送ったもの
- `requested`/`actual`：reviewerのモデル
- `pending`・`pendingHead`・`pendingThreadId`

競合解消などで上流を取り込んで基点を更新する場合だけ`--update-base`を付ける。

## レビュー時の確認事項

worker checkoutでレビューし、branchやcheckoutは変更しないでください。
受信メタデータにsource_thread_idがあればworkerのチャットIDと照合し、不一致は判定保留にしてください。
ローカル固定SHA差分をレビューし、PRとCIはPRのheadが候補SHAと一致する場合だけ根拠にしてください。
base branchが進んだことだけを理由にLGTMを保留しないでください。
参照文書に根拠がなく、人が答えないと決まらない判断は、決めた点・選んだもの・推奨を確認事項として結果に含めてください。
確認事項だけを理由にLGTMを保留しないでください。

## Claude CodeのCloud

`harnexus-task environment`が`"host":"claude"`を返す場合、reviewerは同じVMのCodex CLIで動き、Appのチャットは使わない。
依頼JSONのcheckoutはリポジトリの最上位でよく、projectIdにはリポジトリ名を入れる（list_projectsは使わない）。
`harnexus-task review --request <JSON>`はレビューが終わるまで戻らず、1〜2分かかる。
Bashのtimeoutを600000ms以上にするか、バックグラウンドで実行して終了を待つ。
出力の`status`が`completed`なら、`verdict`・`answer`・`base`・`head`をそのまま結果として扱う。
`state --request`・wait_threads・read_threadは使わない。
修正後は同じJSONで再実行し、同じreviewerに再レビューさせる。
同じheadは拒否されるため、修正をcommitしてから再実行する。
出力が結果不明（`--recover discard`の案内）なら再実行せず、報告して停止する。
reviewerを確かめたうえでownerが送り直すと決めた場合だけ、`--recover discard`を付けて実行する。
