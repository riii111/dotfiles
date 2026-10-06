# 依頼JSON

初回はlist_projectsでGit repositoryとisGitRepositoryを確認してprojectIdを選び、次を`.reviewctl/request.json`へ保存する。

```json
{
  "taskId": "TR1",
  "documentRefs": ["/absolute/path/to/task.md", "/absolute/path/to/AGENTS.md"],
  "workerAI": "Codex",
  "workerChatId": "worker自身の確定チャットID",
  "projectId": "repositoryのprojectId",
  "checkout": "/absolute/path/to/worker-checkout",
  "baseBranch": "origin/main",
  "prUrl": null
}
```

workerAIはCodexまたはClaude。taskIdは管理元内の対象識別子。documentRefsは管理元を先頭に置く絶対パス・HTTPS URLの配列で、合意・規約・判断記録も文書として参照する。資料本文や補足文をJSONへ入れない。

baseBranchはローカルまたはremote追跡branch名。初回prepareがそのtipとcheckoutのHEADからbase/head SHAを固定し、recordまでにHEADが変わった場合は記録を拒否する。再レビューは同じbase SHAと新しいHEADを使う。上流を取り込んで基点を更新する場合だけprepareとrecordに--update-baseを付ける。

prUrlはPRのURL。未作成ならnullまたは項目省略。PRのheadと候補SHAの一致はreviewerが確認する。
依頼JSONは結果を受け取るまで保持し、生成されたtool・argumentsを追記や言い換えなしで送信する。

旧形式のstateも同じreviewerで再開する。旧形式でpendingのときは元の依頼JSONで先にrecordし、その後に上記形式へ移行する。stateの削除や新規reviewerの再作成は不要。
