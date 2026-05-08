---
description: |
  実装済みの変更を、正しさ・一貫性・実用上の品質の観点でレビューする。
  指摘と調査メモを混ぜず、投稿すべきレビューコメントを明確に分ける。
argument-hint: "[-sec] [-lite]"
---

# code-review

レビューだけを行う。実装はしない。

## Args
- `-sec`: auth / 入力 / secret / network などの安全性に関わる変更で security-reviewer を追加する
- `-lite`: blocker 中心の短い出力にする。Phase 0 を省略して Quick として扱う

## Phase 0: レビューモード確認

`-lite` の場合は省略して Quick にする。

それ以外はユーザーに確認する:
1. Review mode: Quick / Standard / Deep
2. Focus areas: 任意

モード対応:
- Quick: solo review
- Standard: code-reviewer + consistency-reviewer subagents
- Deep: team review + security-reviewer subagent

`-sec` がある場合は、モードに関係なく security-reviewer を追加する。

## Review team

### Quick
subagent は使わない。自分で correctness と consistency を見る。

### Standard
複数モジュール・複数レイヤー、新しい抽象/API、repo全体の一貫性リスクがありそうな場合に使う。

#### code-reviewer
- correctness
- readability
- 不要な分岐やfallback
- 実際の failure mode に基づかない defensive code
- test / validation gap

#### consistency-reviewer
- naming consistency
- layering / responsibility fit
- duplication vs reuse
- 近傍コードとの不整合
- 小さな局所リファクタで一貫性が上がるか
- 局所的には便利でも repo 全体では off-pattern になっていないか

### security-reviewer
Deep、または `-sec` のときに追加する。

見る観点:
- auth / authz
- input validation
- secret / config handling
- unsafe file / network behavior

## Output format

通常は次の枠で返す:
- Blocking
- Non-blocking
- Consistency / refactor opportunities
- Fix now vs later
- Notes / verification

`-lite` の場合:
- Blocking を先に出し、その後に価値の高い Non-blocking comment を最大3件だけ出す
- 指摘かどうかの混乱を避ける必要がある場合だけ Notes / verification を出す

### Findings vs notes

`Blocking`、`Non-blocking`、`Consistency / refactor opportunities` には、actionable なレビューコメントだけを書く。

以下は finding にしない:
- 実装が妥当だと確認できた調査結果
- 修正を求めない subagent summary
- 実行していない test / check
- 具体的な変更要求ではない前提・注意点・product/dashboard 依存

それらは `Notes / verification` に置く。merge 前に確認すべき caveat なら、具体的な `Blocking` または `Non-blocking` comment として書く。

投稿すべきレビューコメントはそれと分かる形にする。単なる文脈情報は note として明示する。

## Review style

明確に今やる価値があるものだけ提案する。
「このタスクを止めるもの」と「後で改善できるもの」を分ける。
