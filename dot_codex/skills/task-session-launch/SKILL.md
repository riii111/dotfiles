---
name: task-session-launch
description: |
  開始対象taskのCodex TaskをGit worktreeで作成し、タイトルと具体的な`prompt`を設定する。
  `$task-orchestration`から開始対象を受け取ったときに使う。
---

# Task Session Launch

## 手順

1. `codex_app__list_projects`を一度呼び、repositoryに対応するprojectIdを決める。
2. [起動依頼JSON](references/request.md)を保存し、`$HOME/bin/tasklaunch --request <JSONのパス>`を実行する。
3. 生成されたtitleとpromptをそのまま使い、create_threadの入力を組み立てる。
   - Git repositoryではtarget.environment.typeをworktreeにする。
   - startingStateは開始branchを明示された場合だけ指定する。
   - modelはclaude-opus-5-5、thinkingはmediumを既定とし、ユーザーの明示指定を優先する。
4. create_threadを一度呼ぶ。
5. 確定threadIdを確認し、[ID通知](references/worker-identity.md)をsend_message_to_threadでそのworkerへ一度送る。Codex Task IDとして扱い、ClaudeのセッションIDとは区別する。

## 参照文書

合意・制約・依存成果・担当境界は文書へ記録し、worktreeへ入らない資料や規約もdocumentRefsで渡す。先頭はタスク管理元とする。
tasklaunchが[起動依頼](references/worker.md)とtask-workerの実在するリンクから定型文を作る。生成後の追記や言い換えは行わない。未導入なら停止して不足を報告する。

clientThreadIdはworktree準備中の受理結果であり、重複作成しない。
