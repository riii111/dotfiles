---
name: task-review-cycle
description: |
  `$task-worker`のローカル固定SHA差分を独立review Taskでレビューし、修正と再レビューをLGTMまで反復する。
  レビュー工程の開始・再開時に使う。
---

# Task Review Cycle

commit済み候補をfreshなCodex reviewerへ渡し、以後は同じreview Taskで続ける。修正・検証・review基点・完了条件は[task-worker](../task-worker/SKILL.md)に従う。

## 依頼と結果の受取

`$HOME/bin/reviewctl`が未導入ならユーザーに伝えて停止する。
worktreeに`.reviewctl/`を作り、[依頼JSON](references/request.md)を`.reviewctl/request.json`へ保存する。

1. `$HOME/bin/reviewctl prepare --request .reviewctl/request.json`を実行し、返されたtool名とargumentsを下表のツールへ渡す。ユーザーがモデル設定を指定した場合だけ`--model`・`--thinking`を渡す。
2. 送信受理と確定threadIdを確認し、`$HOME/bin/reviewctl record --request .reviewctl/request.json --reviewer-thread-id <確定ID>`で記録する。Codexはturnを終了し、Claudeはwait/readを続ける。
3. 最終回答のbase/headがstateに記録された候補と一致することを確認する。修正後は同じJSONのPR URL・参照文書を必要に応じて更新し、再依頼する。SHAはreviewctlが取得する。判定保留なら不足を解消する。

| worker | 送信ツール | 結果の受取 |
| --- | --- | --- |
| Codex | `codex_app__create_thread` / `codex_app__send_message_to_thread` | reviewerの返信で次turnを開始 |
| Claude | harnexusの`create_thread` / `send_message_to_thread` | `wait_threads` / `read_thread` |

Claudeはwait_threadsのtimeoutMsを60000以下にし、cursorを次のafterCursorへ渡す。正常timeoutでは待機を続け、対象別errors・失敗・中断は理由を確認する。最終回答が足りなければread_threadで読み、commentaryだけで判定しない。
read_threadは最新1turn・出力なしから読み、不足する履歴や出力だけ追加取得する。CLIの実行補助が必要なら[復旧時の受け渡し](references/recovery.md)に従う。
初回prepareは作成結果待ちのstateを保存する。送信結果が不明、またはclientThreadIdだけなら[作成結果の復元](references/creation.md)に従い、新規作成を再送しない。
Claude workerのreviewerはCodexモデルに限られる。Claudeモデルを指定された場合は、対応するモデルの指定を求める。

## 再開と基点更新

`$HOME/bin/reviewctl state`でreviewerと候補を確認する。
競合解消などで上流を取り込んで基点を更新する場合だけ、prepareとrecordの両方に`--update-base`を付ける。

## レビュー時の確認事項

worker checkoutでレビューし、branchやcheckoutは変更しないでください。
受信メタデータにsource_thread_idがあればworkerのチャットIDと照合し、不一致は判定保留にしてください。
ローカル固定SHA差分をレビューし、PRとCIはPRのheadが候補SHAと一致する場合だけ根拠にしてください。
base branchが進んだことだけを理由にLGTMを保留しないでください。
