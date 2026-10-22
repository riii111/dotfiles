# 起動依頼JSON

```json
{
  "taskId": "TR1",
  "documentRefs": [
    "/absolute/path/to/task.md",
    "https://linear.app/example/issue/EX-1",
    "/absolute/path/to/AGENTS.md"
  ],
  "completionTarget": "draft_pr",
  "projectId": "repositoryのprojectId"
}
```

- taskId: 管理元で対象を特定する識別子。
  Issue番号や文書内のTR1など。
- documentRefs: 管理元を先頭に置く、絶対パスまたはHTTPS URLの配列。
  合意・規約・判断記録も必要な参照だけ加える。
- completionTarget: ユーザーが許可した到達点。
  implementationは実装・検証、draft_prはDraft PR・CI成功、mergeはマージまで。
- projectId: list_projectsで選んだGit repositoryのprojectId。
- startingBranch: 任意。
  ユーザーが開始branchを明示した場合と、[PRの積み方](stacking.md)で積むと決めた場合だけ指定する。
  省略時はprojectのdefault branchから作る。
- displayName: 任意。
  スレッド一覧で仕事が分かる一行の名前で、Issueのタイトルなどを使う。
  指定するとスレッド名は`Impl｜<displayName>`、省略時は`Impl <taskId>`になる。
  表示だけに使い、既存workerの判定には使わない。

補足や資料本文は参照文書へ記録する。
JSONは上記の項目だけを使う。
