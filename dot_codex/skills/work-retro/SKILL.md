---
name: work-retro
description: |
  直近の会話ログ（Claude Code・Codex）と権限確認の記録から、ownerが繰り返し伝えている指示や、workerが止まった箇所を集計し、仕組みの改善を提案する。
  週次のScheduled Taskと、「振り返り」「work-retro」と言われたときに使う。
---

# Work Retro

`~/ghq/github.com/riii111/agents-retro/skills/agents-retro/SKILL.md`を読み、その手順と報告の書式に従う。
そのうえで、次の値と手順を加える。

## 入力

- 日数：指定がなければ7日。
- パターン：`~/.codex/skills/work-retro/references/patterns.json`
- 出力先：`~/agent-desk/retro`。
  gitでは管理しない。

## 追加の手順

- agents-retroを実行した後、`permission-analyze`スキルを読み、同じ日数で権限確認・自動モードの拒否・サンドボックスの失敗を集計する。
  その手順と制約に従い、改善候補を振り返りの報告に含める。
- 各所見の変更先は、次の順で選ぶ。
  - hook・設定・スクリプト：dotfiles（`chezmoi source-path`で管理元を調べる）
  - harnexusの拡張：`~/ghq/github.com/riii111/harnexus`。
    スレッド間の受け渡し、`harnexus-task`のコマンド、外部の出来事を起点にしたworkerへの送信など、AppとAIの境界にある処理
  - skillの手順：`task-*`などの該当skill
  - 指示文（CLAUDE.md・AGENTS.md）：上のどれでも解消できない場合だけとし、確実性が低いと明記する

## 制約

- 定期実行では提案と報告の作成だけを行い、dotfiles・harnexus・skill・`patterns.json`は変更しない。
  変更は、会話でownerが提案を選んだ場合だけ行う。
- 最終回答は報告の本文だけにする。
