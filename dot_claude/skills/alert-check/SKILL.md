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

OPEN ステータスの各グループに対して `pe trace <groupId> --json` を実行する。

優先順位:
- `relatedTo` の子グループは親だけ trace する（子は省略）
- `lastSeen` が新しい順、`count` が多い順で優先

#### retryCheck の解釈ルール

`retryCheck` はエンドポイント単位の集計であり、**失敗した個別リクエストの再試行結果ではない**。

- `verdict: "recovered"` → 「同じエンドポイントに後続の成功リクエストがある」だけ。失敗したリクエスト自体が回復したとは限らない
- 報告では「エンドポイントは正常稼働」とは書いてよいが、「リトライ後回復」「当該リクエストが成功」とは書かない
- 個別リクエストの回復を確認するには、lifecycle 内の識別子（組織ID等）で Cloud Logging を直接検索する必要がある

#### lifecycle の適用範囲

`pe trace` が返す lifecycle は **直近1件のイベントのみ** である。

- lifecycle から判明した原因（例: 外部API 502）は「直近1件の原因」として報告する
- 複数件の発生がある場合、全件に同じ原因を一般化してはならない
- 「直近トレースでは〇〇を確認。他N件は未確認」と明記する

### Step 3: 対応 PR/Issue の検索

以下のキーワードで PR と Issue の両方を検索する:

```bash
gh pr list --search "<keyword>" --state all --json number,title,url,state --limit 5
gh issue list --search "<keyword>" --state all --json number,title,url,state --limit 5
```

検索キーワード（順に試す）:
1. サービス名
2. 例外クラス名
3. エラーメッセージの安定した断片（先頭20-30文字程度）

紐付けルール:
- タイトルや本文に **サービス名 + 例外クラス** など複数の根拠が揃えば「対応PR/Issue」とする
- 単一キーワードの一致だけなら「関連候補」に留め、断定しない
- 該当なしなら「未特定」とする

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
- **根拠**: （事実ベースで記述。Last seen, PR有無, trace結果, retryCheck verdict など。**不明な点も明記する**: 原因不明、ユーザー影響不明 等）
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
| PR/Issueなし & 散発的（増加傾向なし）& **原因が推定できている** & ユーザー影響なし | 散発エラー（対処不要） | medium |
| 上記いずれにも該当しない（原因不明、影響不明を含む） | 要確認 | low |

重要:
- 「解決済み」は対応PRのマージなど強い根拠がある場合のみ使う。Last seen が古いだけでは「再発観測なし」に留める
- 「散発エラー（対処不要）」は **原因が推定できていること** が前提。原因不明 or ユーザー影響不明なら、低頻度でも「要確認」にする
- 判断できないことは断言せず「不明」と書く。「〜と推定」「〜の可能性」で逃げない

## Important Notes

- 取得は必ず `--json`、報告だけ自然文にする
- 根拠不足なら断定せず「要確認」とする
- `pe` コマンドが使えない場合はユーザーに報告して終了する
- GCP 認証が切れている場合は `gcloud auth login` を案内する
- コードの修正は行わない。分析と報告のみ
