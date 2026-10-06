# 起動依頼JSON

```json
{
  "taskId": "TR1",
  "documentRefs": [
    "/absolute/path/to/task.md",
    "https://linear.app/example/issue/EX-1",
    "/absolute/path/to/AGENTS.md"
  ],
  "completionTarget": "draft_pr"
}
```

- taskId: 管理元で対象を特定する識別子。Issue番号や文書内のTR1など。
- documentRefs: 管理元を先頭に置く、絶対パスまたはHTTPS URLの配列。合意・規約・判断記録も必要な参照だけ加える。
- completionTarget: ユーザーが許可した到達点。implementationは実装・検証、draft_prはDraft PR・CI成功、mergeはマージまで。

補足や資料本文は参照文書へ記録する。JSONは上記の項目だけを使い、title・promptはtasklaunchの出力をそのまま渡す。
