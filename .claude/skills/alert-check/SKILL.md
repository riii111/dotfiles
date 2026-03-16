---
description: Production alert check — run pe (prod-errors) to triage today's alerts, analyze root causes, and produce a duty report.
argument-hint: [summary|trace <groupId>] (default: full check)
---

# Production Alert Check

`pe` (prod-errors) スクリプトを使って本番アラートを確認・分析し、当番向けの報告を生成する。

## Arguments

Parse `$ARGUMENTS`:

- (empty) → フルチェック（summary → 各グループの trace → 分析 → 報告）
- `summary` → サマリーのみ表示
- `trace <groupId>` → 特定グループの深掘り

## Execution Flow

### Step 1: サマリー取得

```bash
pe summary
```

エラーが0件なら「新規アラートなし」と報告して終了。

### Step 2: 各エラーグループの深掘り

OPEN ステータスの各グループに対して:

```bash
pe trace <groupId>
```

### Step 3: 分析

各エラーについて以下を判断する:

1. **既知 or 新規**: 過去に見たエラーパターンか、初見か
2. **対応状況**: 既に PR / Issue が存在するか（`gh pr list --search "<keyword>"` や `gh issue list --search "<keyword>"` で確認）
3. **解決済みか**: Last seen が古い場合、再発していないか。trace の Retry Check 結果も参照
4. **Related マーク**: `→ #N?` が付いているグループは同一起因の可能性が高いのでまとめて分析

### Step 4: 報告生成

以下のフォーマットで報告を出力する:

```
## 本日のアラート状況（YYYY-MM-DD）

### サマリー
- OPEN: N件（うち新規: M件）
- 対応済み: X件 / 要対応: Y件

### 各アラートの詳細

#### [エラー名] — [サービス名]
- **ステータス**: 解決済み / 対応中 / 要エスカレーション
- **根拠**: （なぜそう判断したか。Last seen, PR有無, trace結果などを具体的に）
- **対応PR/Issue**: （あれば URL）
- **アクション**: 不要 / PR レビュー推奨 / チームに共有すべき

### エスカレーション事項
（要対応のアラートがあればここにまとめる。なければ「なし」）
```

## Judgment Criteria

以下の基準でステータスを判断する:

| 条件 | 判断 |
|------|------|
| 対応PRがマージ済み & Last seen が古い | 解決済み |
| 対応PRがOPEN | 対応中（PRレビュー推奨） |
| PR/Issueなし & 直近も発生している | 要エスカレーション |
| PR/Issueなし & Last seen が古い（3日以上前） | 解決済み（自然解消の可能性）。ただし根本原因不明なら共有推奨 |

## Important Notes

- `pe` コマンドが使えない場合はユーザーに報告して終了する
- GCP 認証が切れている場合は `gcloud auth login` を案内する
- 判断に迷う場合は「要確認」として報告し、ユーザーに判断を委ねる
- コードの修正は行わない。分析と報告のみ
