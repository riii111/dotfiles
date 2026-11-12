---
name: ja-doc-polish
description: 指定されたMarkdownファイルの日本語を読みやすく書き直し、日本語mdのlintとfmtを通す。「わかりやすくして」「推敲して」「lint・fmtをかけて」と言われたときに使う。
---

# ja-doc-polish

指定されたファイルだけを書き直し、内容の事実と結論は変えない。

## 書き直す

作業前に `../japanese-tech-writing/SKILL.md` を読み、その規範で書き直す。
lintとfmtで直せる点は、そちらに任せる。
あわせて次を守る。

- 並列は箇条書き、対応関係は表、項目と説明は「**語**：説明」で書く。
- 処理の流れ、状態の遷移、依存関係は、文章より読みやすければMermaidの図にする。
- 表の1つのセルには1つの値だけを書く。
  複数の値が入るなら、行か列に分ける。
- PRやIssueを番号だけで書かない。
  読み手に中身を読ませる例なら、タイトルとリンクを付ける。
  文書の趣旨に関わらない番号なら、その情報ごと消す。

## lintとfmt

`~/ghq/github.com/riii111/dotfiles/scripts/ai-docs` を使う。
観点と基準は同じディレクトリの `README.md` にある。

```sh
npm --prefix ~/ghq/github.com/riii111/dotfiles/scripts/ai-docs run lint -- <ファイル>
npm --prefix ~/ghq/github.com/riii111/dotfiles/scripts/ai-docs run fmt -- <ファイル>
```

lintの警告を直してからfmtをかけ、最後にもう一度lintを実行する。
警告が残るときは、残した理由を報告する。
