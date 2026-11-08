---
name: pr-watch-link
description: |
  このチャットにPRの監視を登録し、レビュー指摘・CodeRabbitの完了・コンフリクト・必須CIの失敗を届くようにする。
  「このPRを監視して」「PRの指摘をここに届けて」と頼まれたときに使う。
---

# PR Watch Link

`harnexus-crew environment`が`"host":"claude"`を返す場合は、先に末尾の「Claude CodeのCloud」を読む。

1. `pr-wake watch link <PRのURL>`をサンドボックス外で一度実行する。
   先に引数なしの`pr-wake watch`で使い方を表示する。
   `pr-wake`が未導入か、使い方に`watch link`がなければ、`harnexus-crew watch --link <PRのURL>`を使う。
   Codexは`sandbox_permissions: require_escalated`を付け、Claudeはそのまま実行する。
   パイプ・リダイレクト・`cd`などを付けず単独で実行する。
2. 成功したら、出力の`watched`のURLを伝える。
   出力に`warning`があれば、そのまま伝える（送信元がなく、知らせが届かない状態）。
   失敗したら再実行せず、「PRは監視されていない」とエラーを伝える。
   別のチャットがすでに監視しているPRは登録できず、そのチャットIDがエラーに出る。
   PRのURLは`https://github.com/<owner>/<repo>/pull/<番号>`の形が必要。

届いた知らせへの対応は、task-workerの「PRへの指摘対応」に従う。
知らせは、ownerが`pr-wake watch sender`で登録した送信用チャットから届く。

## Claude CodeのCloud

`harnexus-crew environment`が`"host":"claude"`を返す場合、この節が手順1〜2と送信用チャットの説明に代わる。
`pr-wake watch`は使えないため、`subscribe_pr_activity`でPRをこのセッションに購読する。
購読できたらPRのURLを伝え、失敗したり別のエージェントが監視中と返ったりしたら「PRは監視されていない」と伝える。
知らせはPRの出来事としてこのセッションに届く。
