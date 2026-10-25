---
name: permission-analyze
description: Claude Code の権限確認・auto モードの拒否・Bash サンドボックスで止まったコマンドを集計し、設定の改善を提案する。「サンドボックスが不便」「権限確認が多い」「permission-analyze」と言われたとき、または週次の定期実行で使う。
---

`~/ghq/github.com/riii111/agents-retro/skills/permission-analyze/SKILL.md` を読み、集計・解釈・制約・報告の手順に従う。
設定の管理元と適用には、次の手順を使う。

## 設定の管理元

`chezmoi source-path ~/.claude/settings.json` で管理元を調べる。
実ファイルと管理元の `permissions`、`autoMode`、`sandbox` を読む。

## 変更するとき

利用者が候補を選んだら、管理元の `settings.json.tmpl` を編集する。
管理元リポジトリの AGENTS.md に従ってテストし、コミットする。
`chezmoi apply ~/.claude/settings.json` で適用し、`chezmoi diff ~/.claude/settings.json` が空であることを確かめる。

報告は日本語で短く書く。
