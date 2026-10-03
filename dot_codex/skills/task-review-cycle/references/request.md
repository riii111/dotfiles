# 依頼JSON

初回は既存のlist_projectsでGit repositoryとisGitRepositoryを確認してprojectIdを選び、次を`.reviewctl/request.json`へ保存する。

```json
{
  "identifier": "task-id",
  "worker": "Codex",
  "workerId": "worker自身の確定Task ID",
  "projectId": "repositoryのprojectId",
  "checkout": "/absolute/path/to/worker-checkout",
  "base": "固定した完全commit SHA",
  "head": "commit済み候補の完全commit SHA",
  "pushed": false,
  "pr": null,
  "context": "課題・期待する挙動・制約・対象外と管理元の該当節"
}
```

workerは`Codex`または`Claude`。checkoutはworkerの絶対パス。未push候補はPRがあってもpushedをfalseにし、PR未作成ならprをnullにする。
contextには実装者の思考履歴・過去サイクル・前回の指摘を入れない。
