---
name: task-session-launch
description: |
  開始対象taskのworker TaskをGit worktreeで作成する。`harnexus-task`が定型promptを生成して送信する。
  `$task-orchestration`から開始対象を受け取ったときに使う。
---

# Task Session Launch

## 手順

1. `codex_app__list_projects`を一度呼び、repositoryに対応するprojectIdを決める。
2. [起動依頼JSON](references/request.md)を保存する。
3. `harnexus-task launch --request <JSONの絶対パス>`をサンドボックス外で一度実行する。Codexは`sandbox_permissions: require_escalated`を付ける。Claudeはそのまま実行する（サンドボックス対象外）。
   - 既定はclaude-opus-5-5・medium。ユーザーが別モデルを指定した場合だけ`--model`・`--thinking`を渡す。
4. 出力のthreadId・model・effortを報告する。失敗時は理由を報告して停止し、create_threadを直接呼ばない。

同じprojectIdとtaskIdの再実行は既存workerを返し、新規作成しない。結果不明・モデル不一致は`harnexus-task state --request <JSON>`で確認し、ユーザーがAppで確認した結果だけを、承認を得て`harnexus-task resolve --request <JSON> --sent [--thread-id <ID>]`または`--not-sent`で記録する。

## 参照文書

合意・制約・依存成果・担当境界は文書へ記録し、worktreeへ入らない資料や規約もdocumentRefsで渡す。先頭はタスク管理元とする。
harnexus-taskが[起動依頼](references/worker.md)とtask-workerの実在するリンクから定型文を作り、そのまま送る。未導入なら停止して不足を報告する。
