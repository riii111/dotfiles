---
description: Production alert check — run pe (prod-errors) to triage alerts, analyze root causes, and produce a duty report.
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

必ず `--json` で取得する（パース精度のため）。

```bash
pe summary --json
```

エラーが0件なら「新規アラートなし」と報告して終了。

### Step 2: 各エラーグループの深掘り

OPEN ステータスの各グループに対して:

```bash
pe trace <groupId> --json
```

`relatedTo` が付いているグループは同一起因の可能性が高いのでまとめて分析する。

### Step 3: 対応 PR/Issue の検索

以下の順で検索し、最初にヒットしたものを使う:

1. サービス名: `gh pr list --search "<service名>" --state all --json number,title,url,state --limit 5`
2. 例外クラス名: `gh pr list --search "<ExceptionClass>" ...`
3. エラーメッセージの安定した断片（先頭20-30文字程度）

曖昧一致の場合は「関連候補」と明記し、断定しない。

### Step 4: 報告生成

```
## アラート状況（YYYY-MM-DD）

### サマリー
- OPEN: N件
- 対応済み: X件 / 要対応: Y件

### 各アラートの詳細

#### [エラー名] — [サービス名]
- **判定**: 解決済み / 対応中 / 再発観測なし / 要確認 / 要エスカレーション
- **信頼度**: high / medium / low
- **根拠**: （事実ベースで記述。Last seen, PR有無, trace結果, retryCheck verdict など）
- **対応PR/Issue**: （あれば URL。候補の場合はその旨明記）
- **アクション**: 不要 / PR レビュー推奨 / チームに共有すべき

### エスカレーション事項
（要対応のアラートがあればここにまとめる。なければ「なし」）
```

## Judgment Criteria

| 条件 | 判定 | 信頼度 |
|------|------|--------|
| 対応PRがマージ済み & Last seen が古い | 解決済み | high |
| 対応PRがOPEN | 対応中 | high |
| PR/Issueなし & 直近も発生している | 要エスカレーション | high |
| PR/Issueなし & Last seen が古い（3日以上） | 再発観測なし | medium |
| 根拠が不十分 | 要確認 | low |

重要: 「解決済み」は対応PRのマージなど強い根拠がある場合のみ使う。Last seen が古いだけでは「再発観測なし」に留める。

## Important Notes

- 取得は必ず `--json`、報告だけ自然文にする
- 根拠不足なら断定せず「要確認」とする
- `pe` コマンドが使えない場合はユーザーに報告して終了する
- GCP 認証が切れている場合は `gcloud auth login` を案内する
- コードの修正は行わない。分析と報告のみ
