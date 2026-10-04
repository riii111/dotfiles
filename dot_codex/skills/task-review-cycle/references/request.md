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
再依頼でもcontextは省略せず、現在の前提を完全に保存する。prepareは送信受理後にrecordしたcontextと比較して再送の要否を決める。
依頼JSONはレビュー結果を受け取るまで保持し、送信後に候補や前提を更新しない。
