---
description: Production alert triage using `pe`, `gh`, and `gcloud`.
---

# alert-check

本番アラートを `pe` で確認し、必要なら `gh` と `gcloud` で根拠を補強して、当番向けに短く報告する skill なのだ。

## Workflow

1. `pe summary --json` を実行して全体を把握するのだ。
2. `OPEN` のグループだけを優先して `pe trace <groupId> --json` を掘るのだ。
3. 必要なら `gh pr list` と `gh issue list` で対応候補を探すのだ。
4. 必要なら `gcloud logging read` で識別子ベースの裏取りをするのだ。
5. 最後に、事実ベースで短い報告をまとめるのだ。

## Rules

- 取得は原則 `--json` を使うのだ。
- 事実が足りないときは断定しないのだ。
- `retryCheck` は個別リクエストの回復ではなく、エンドポイント単位の集計として扱うのだ。
- `pe trace` の lifecycle は直近 1 件だけだとみなすのだ。
- この skill ではコード修正はしないのだ。分析と報告に徹するのだ。

## Output

報告は次の粒度で短くまとめるのだ。

- サマリー
- 各アラートの判定
- 根拠
- 対応 PR / Issue
- 必要なアクション
