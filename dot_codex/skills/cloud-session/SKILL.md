---
name: cloud-session
description: |
  Claude CodeのCloudセッションを新しく始めるか既存のものを引き継ぎ、Codex AppのClaudeチャットで見て話せるようにする。
  「これをCloudでやって」「このCloudセッションを引き継いで」と頼まれたときに使う。
---

# Cloud Session

1. 新しく始めるか、既存のセッションを引き継ぐかを決める。
   引き継ぐ場合は、対象のセッションのIDか`claude.ai/code`のURLを確かめる。
   分からなければユーザーに聞く。
2. `list_projects`を一度呼び、対象のリポジトリのprojectIdを決める。
   CodexはAppのツール、harnexus内のClaudeは`mcp__codex_link__list_projects`を使う。
   リポジトリが分からなければ、今のチャットのprojectIdを使う。
3. `harnexus-task cloud`をサンドボックス外で一度実行する。
   - 新しく始める：依頼の本文をファイルに保存し、`--prompt-file <そのファイルの絶対パス> --project <projectId>`を付ける。
     本文は、ユーザーの依頼をCloudのClaudeがそのまま読める形にまとめる。
   - 引き継ぐ：`--link <IDかURL> --project <projectId> --title <短い名前>`を付ける。
   - Codexは`sandbox_permissions: require_escalated`を付け、Claudeはそのまま実行する。
     パイプ・リダイレクト・`cd`などを付けず単独で実行する。
     許可の確認が出たら、ユーザーの承認を待つ。
4. 成功したら、出力のthreadIdのチャットでそのセッションを見られることと、出力のurlを伝える。
   失敗したら再実行せずエラーを伝え、create_threadを直接呼ばない。
   新しく始めたセッションは失敗しても動き続けるので、エラーに出たセッションIDも伝える。

開いたチャットは、最初のメッセージの`/cloud`でセッションにつながる。
そのセッションが別のセッションを始めると、そのチャットも自動で開く。
すでに別のチャットにつながっているセッションは、そのチャットで断られる。
