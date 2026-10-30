---
name: cloud-session
description: |
  Claude CodeのCloudセッションを、Codex AppのClaudeチャットで見て話せるようにする。
  「このCloudセッションを引き継いで」「Cloudで進めている作業をAppで見たい」と頼まれたときに使う。
---

# Cloud Session

1. 対象のCloudセッションのIDか`claude.ai/code`のURLを確かめる。
   分からなければユーザーに聞く。
2. `list_projects`を一度呼び、セッションのリポジトリのprojectIdを決める。
   CodexはAppのツール、harnexus内のClaudeは`mcp__codex_link__list_projects`を使う。
   リポジトリが分からなければ、今のチャットのprojectIdを使う。
3. `harnexus-task cloud --link <IDかURL> --project <projectId> --title <短い名前>`をサンドボックス外で一度実行する。
   Codexは`sandbox_permissions: require_escalated`を付け、Claudeはそのまま実行する。
   パイプ・リダイレクト・`cd`などを付けず単独で実行する。
4. 成功したら、出力のthreadIdのチャットでそのセッションを見られると伝える。
   失敗したら再実行せずエラーを伝え、create_threadを直接呼ばない。

開いたチャットは、最初のメッセージの`/cloud`でセッションにつながる。
すでに別のチャットにつながっているセッションは、そのチャットで断られる。

新しいCloudセッションは、Codex AppやCLIから対話なしには作れない。
claude.ai/codeかClaudeアプリで始めてもらい、そのURLでこの手順を進める。
