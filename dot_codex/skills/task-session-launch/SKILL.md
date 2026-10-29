---
name: task-session-launch
description: |
  開始対象taskのworker TaskをGit worktreeで作成する。`harnexus-task`が定型promptを生成して送信する。
  `$task-orchestration`から開始対象を受け取ったときに使う。
---

# Task Session Launch

## 手順

最初に[実行環境の切り替え](../task-worker/references/environment.md)に従って環境を判定する。
Cloudでは別タスクを作らず、その文書の「Claude workerの起動」に従って現在のタスク内でClaude workerを起動する。
以下の手順1〜4はローカル用で、Cloudでは使わない。

1. `list_projects`を一度呼び、repositoryに対応するprojectIdを決める。
   CodexはAppのツール、harnexus内のClaudeは`mcp__codex_link__list_projects`を使う。
2. [起動依頼JSON](references/request.md)を保存する。
3. `harnexus-task launch --request <JSONの絶対パス>`をサンドボックス外で一度実行する。
   Codexは`sandbox_permissions: require_escalated`を付ける。
   Claudeはそのまま実行する（サンドボックス対象外）。
   パイプ・リダイレクト・`cd`などを付けず単独で実行する（付けると対象外にならない）。
   - モデルと思考量は`harnexus-task`の既定に任せる。
     ユーザーが別モデルを指定した場合だけ`--model`・`--thinking`を渡す。
4. 出力のthreadId・model・effortを報告する。
   失敗時は理由を報告して停止し、create_threadを直接呼ばない。

同じprojectIdとtaskIdの再実行は既存workerを返し、新規作成しない。
結果不明・モデル不一致は`harnexus-task state --request <JSON>`で確認する。
最上位の`workerThreadId`・`pending`・`pendingThreadId`・`requested`/`actual`を見る。
ユーザーがAppで確認した結果だけを、承認を得て記録する。
送信済みなら`harnexus-task resolve --request <JSON> --sent [--thread-id <ID>]`、未送信なら`--not-sent`で記録する。

## PRの積み方

積むかどうかの基準は[PRの積み方](references/stacking.md)に従う。
積み方は呼び出す側が決め、この手順では決めない。
積むと決めた場合は、起動依頼JSONにstartingBranchと積み先のPRのURLを入れる。

## 参照文書

合意・制約・依存成果・担当境界は文書へ記録し、worktreeへ入らない資料や規約もdocumentRefsで渡す。
先頭はタスク管理元とする。
harnexus-taskが[起動依頼](references/worker.md)とtask-workerの実在するリンクから定型文を作り、そのまま送る。
未導入なら停止して不足を報告する。
