---
name: reviewing-adrs
description: >
  Reviews a draft ADR and returns structured feedback before team review submission.
  Identifies weak points that are likely to be flagged in review: assumption explicitness,
  forward dependencies, depth of rejection reasoning, data validity, scope of impact,
  writing structure, and codebase/external consistency.
  Use when you want to self-review an ADR draft, anticipate review comments, or
  strengthen the rationale before submitting to the team.
---

# Reviewing ADRs

## 目的

ADR をチームレビューに提出する前に個人で品質を向上させる。
「指摘される前に潰す」「指摘されても打ち返せる」状態を目指す。

## リソース

- **レビュー観点ガイド**: `.claude/reviewing-adrs/references/review-guide.md` — 必ず読む
- **アーキテクチャ文脈**: `.claude/reviewing-adrs/references/arch-context.md` — 観点5（影響範囲）・観点7（整合性確認）の照合に使う
- **ADR テンプレート**: プロジェクトの ADR テンプレートがあれば参照する
- **テクニカルライティングガイド**: プロジェクトのライティングガイドがあれば観点6（文章構造）の基準として参照する

## 実行手順

1. レビュー対象の ADR ファイルパスを受け取る
2. `.claude/reviewing-adrs/references/review-guide.md` を読み、7つの観点と推奨レビュー順を把握する
3. 以下をこの順で読み、プロジェクト固有のコンテキストを把握する:
   - `.claude/rules/` 配下のファイル（アーキテクチャルール・命名規則・実装パターン）
   - `.claude/reviewing-adrs/references/arch-context.md`（既存 ADR インデックス・ADR レビュー固有の補足・関連リポジトリ情報）
   - ADR の内容に応じて、関連する `.claude/skills/` 配下のリファレンスも参照する
   - ADR がインフラ変更を含む場合は `arch-context.md` に記載のインフラリポジトリも参照する
4. ADR を査読し、観点ごとに評価・フィードバックを出力する

## 出力フォーマット

```markdown
## ADR レビュー結果: <ADR タイトル>

### 提出判定
- **判定**: 提出可 / 条件付き提出可 / 提出非推奨
- ブロッカー: <件数> / 要改善: <件数>

判定の目安: ブロッカー >= 1 → 提出非推奨、ブロッカー = 0 かつ 要改善 >= 2 → 条件付き提出可、それ以外 → 提出可。
ただし ADR のスコープや指摘の重みに応じて判断を調整してよい。調整した場合は理由を1行で明記すること。

### 最優先指摘（最大3件、指摘数が3件未満なら実件数のみ）
1. [<観点名>] <問題の要約>
   - 修正案: <具体的なアクション>
   - 想定質問: <レビュアーが突きそうな問い>
   - 回答案: <1-2文>

### 観点別フィードバック

#### [観点名] — <OK / 要改善 / ブロッカー>
<具体的な指摘。ADR の該当箇所を引用して説明する>
<改善案（あれば）>

（指摘なしの観点は「OK — 問題なし」と1行で閉じる）

### チェックリスト
- [ ] コードベース・外部情報との整合性（観点7）
- [ ] 影響範囲とステークホルダー（観点5）
- [ ] 前提崩壊トリガーの明示（観点1）
- [ ] 後続決定の依存関係（観点2）
- [ ] 定量根拠の妥当性（観点4）
- [ ] 却下案の却下理由の深度（観点3）
- [ ] 文章構造と読みやすさ（観点6）
```

## 評価基準

| 評価 | 意味 |
|------|------|
| **OK** | 問題なし |
| **要改善** | レビューで指摘される可能性が高い。提出前に対処推奨 |
| **ブロッカー** | このままでは承認されない可能性が高い |

## 注意

- このプロジェクトの ADR は基本品質が高いため、「代替案を列挙しているか」「NFR があるか」等の基本チェックは省略してよい
- 観点ガイドの「刺さりやすいパターン」を優先的に照合すること
- レビューで指摘される穴だけでなく、実装フェーズで顕在化しうる設計上の見落としにも注意を払うこと
- 問題が見当たらない観点は「OK — 問題なし」と短く記載し、冗長な説明を避けること

## レビュー後の振り返り（任意）

チームレビューで実際に受けた指摘を `/learn` コマンドで記録し、次回以降のレビュー精度を高める。
記録先は `~/.claude/cache/learnings/` 配下のプロジェクト別 `adr/` フォルダに集約する。

記録すべき内容:
- この Skill が見落としていた「刺さりやすいパターン」
- プロジェクト固有の制約で、arch-context.md に追記すべきもの
