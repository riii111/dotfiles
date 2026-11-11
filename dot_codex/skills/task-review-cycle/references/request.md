# 依頼JSON

初回はlist_projectsでGit repositoryとisGitRepositoryを確認してprojectIdを選び、次を`.reviewctl/request.json`へ保存する。
T3 Codeでは`t3_project_list`でprojectIdを選ぶ。

```json
{
  "taskId": "TR1",
  "documentRefs": ["/absolute/path/to/task.md", "/absolute/path/to/AGENTS.md"],
  "workerAI": "Codex",
  "projectId": "repositoryのprojectId",
  "checkout": "/absolute/path/to/worker-checkout",
  "baseBranch": "origin/main",
  "prUrl": null
}
```

workerAIはCodexまたはClaudeで、reviewerの返却方法を決める。
taskIdは管理元内の対象識別子。
documentRefsは管理元を先頭に置く絶対パス・HTTPS URLの配列で、合意・規約・判断記録も文書として参照する。
資料本文や補足文をJSONへ入れない。
workerのチャットIDはharnexus-crewが`CODEX_THREAD_ID`から取得する。
checkoutは`~/.codex/worktrees/`配下のworker worktreeに限る。
T3 Codeでは、チャットIDを`T3CODE_THREAD_ID`から取得し、checkoutは`~/.t3/worktrees/`配下に限る。

baseBranchはローカルまたはremote追跡branch名。
初回にそのtipとcheckoutのHEADからbase/head SHAを固定する。
再レビューは同じbase SHAと新しいHEADを使う。
上流を取り込んで基点を更新する場合だけ`--update-base`を付ける。

prUrlはPRのURL。
未作成ならnullまたは項目省略。
PRのheadと候補SHAの一致はreviewerが確認する。

displayNameは任意で、スレッド一覧で仕事が分かる一行の名前。
起動依頼のdisplayNameやIssueのタイトルを使う。
指定するとreviewerのスレッド名は`Review｜<displayName>`、省略時は`Review <taskId>`になる。

stateはharnexus-crewが`~/.local/state/harnexus-crew/`に保存する。
reviewctlの`.reviewctl/state.json`に確定済みreviewerがあれば読み取り、同じreviewerで再開する。
作成待ちのまま残った旧stateは拒否されるため、Appで確認してreviewerがなければ削除する。
