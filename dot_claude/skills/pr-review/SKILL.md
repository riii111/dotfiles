---
name: pr-review
description: >
  PRレビューを実施するスキル。他者のPRにも自分のPRにも使える。
  "PRレビュー", "PR review", "レビューして", "review PR", "review pull request",
  PR URLが渡された場合に使用する。
  subagentによる並列レビュー、Codex/CodeRabbit連携を行う。
---

# PR Review Skill

```
Phase 0: ユーザー確認                 ← このファイルの範囲
Phase 1: Auto-analysis + レビュー実行 ← references/execution.md
Phase 2: 検証・統合・出力             ← references/execution.md
```

---

## Phase 0: ユーザー確認

AskUserQuestion で以下4つの質問を送信すること:

```
レビュー設定を確認させてください:
1. モード: Quick / Standard / Deep
2. 外部ツール（Codex/CR）: する / しない
3. 追加コンテキスト: なし / あり（パス or 貼付）
4. 注力観点（任意）:
```

---

## 次のステップ

ユーザーの回答を受け取ったら `~/.claude/skills/pr-review/references/execution.md` を読み、Phase 1 以降を実行せよ。
