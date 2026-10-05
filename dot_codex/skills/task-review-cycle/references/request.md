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
  "context": "レビュー判断に必要な管理元の参照と、そこにない合意・制約"
}
```

workerは`Codex`または`Claude`。未push候補はPRがあってもpushedをfalseにし、PR未作成ならprをnullにする。
contextは同じ版を読める管理元の参照と追加の合意・制約に絞り、本文・規約・workerのPR作成手順を転載しない。参照できない場合だけ判断に必要な要件を要約する。
管理元の版や追加の合意が変わればcontextも更新する。思考履歴・過去サイクル・前回の指摘は含めず、記録済みcontextと同じならprepareが再送を省く。
履歴復元に使うため、依頼JSONは結果を受け取るまで保持・固定する。
