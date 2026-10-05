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
[依頼JSON](references/request.md)を`.reviewctl/request.json`へ保存する。

1. `$HOME/bin/reviewctl prepare --request .reviewctl/request.json`を実行し、返されたtool名とargumentsを下表のツールへ渡す。ユーザーがモデル設定を指定した場合だけ`--model`・`--thinking`を渡す。
2. 送信受理と確定threadIdを確認し、`$HOME/bin/reviewctl record --request .reviewctl/request.json --reviewer-thread-id <確定ID>`で記録する。Codexはturnを終了し、Claudeはwait/readを続ける。
3. 最終回答のbase/headが依頼と一致することを確認する。修正後は同じJSONのheadとpush/PR状態、変更した前提を更新して再依頼する。判定保留なら不足を解消する。

全文の再送が必要ならprepareに`--full-context`を付ける。

| worker | 送信ツール | 結果の受取 |
| --- | --- | --- |
| Codex | `codex_app__create_thread` / `codex_app__send_message_to_thread` | reviewerの返信で次turnを開始 |
| Claude | harnexusの`create_thread` / `send_message_to_thread` | `wait_threads` / `read_thread` |

Claudeはwait_threadsのtimeoutMsを60000以下にし、cursorを次のafterCursorへ渡す。正常timeoutでは待機を続け、対象別errors・失敗・中断は理由を確認する。最終回答が足りなければread_threadで読み、commentaryだけで判定しない。
送信結果が不明、またはclientThreadIdだけが返された場合はAppの状態を確認し、確定IDを得るまで再送・recordしない。
Claude workerのreviewerはCodexモデルに限られる。Claudeモデルを指定された場合は、対応するモデルの指定を求める。

## 再開と基点更新

`$HOME/bin/reviewctl state`でreviewerと候補を確認する。
競合解消などで上流を取り込んだ場合だけJSONのbaseを更新し、prepareとrecordの両方に`--update-base`を付ける。
