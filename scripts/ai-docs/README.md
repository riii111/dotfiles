# Markdownの検査と整形

日本語の文章とSKILLの参照を検査し、文の区切りとMarkdownの書式を整える。
Node.js 22以上が必要。
以下のコマンドはリポジトリのルートで実行する。

```sh
npm --prefix scripts/ai-docs ci --ignore-scripts
npm --prefix scripts/ai-docs run lint
npm --prefix scripts/ai-docs run links
```

引数を省略すると、Gitで追跡している`dot_codex/skills/`と`dot_claude/skills/`内のMarkdownを検査する。
ファイルを指定すると、そのファイルだけを検査する。パスはリポジトリのルート基準で、絶対パスも使える。
リンク検査は参照先のMarkdownも読み、ファイルとアンカーの存在を確かめる。外部URLへの通信は行わない。

```sh
npm --prefix scripts/ai-docs run lint -- dot_codex/skills/task-dispatch/SKILL.md
npm --prefix scripts/ai-docs run lint -- --strict dot_codex/skills/task-dispatch/SKILL.md
npm --silent --prefix scripts/ai-docs run lint -- --json
```

文章の警告は既定では終了コードを変えない。`--strict`で警告も失敗にする。
リンク切れと実行エラーは失敗になる。

## 整形

```sh
npm --prefix scripts/ai-docs run fmt -- --check dot_codex/skills/task-dispatch/SKILL.md
npm --prefix scripts/ai-docs run fmt -- dot_codex/skills/task-dispatch/SKILL.md
git diff -- dot_codex/skills/task-dispatch/SKILL.md
```

`--check`は変更予定のファイルを表示し、変更があれば失敗する。ファイルは書き換えない。
`fmt`は明示したファイルだけを変更する。
独自ルールの改行修正を適用した後、Prettierで表やリストを整える。
既存の改行とコードブロックの内容を保ち、Markdownの構造や空白以外の文章が変わる場合は整形を中止する。
整形後は差分を確認し、chezmoiの適用を変更対象に限定する。

## 検査するルール

| ルール                       | 基準                                       | 自動修正                                            |
| ---------------------------- | ------------------------------------------ | --------------------------------------------------- |
| `source-line`                | 日本語を含む行は2文まで、2文目は20字以内   | 長い2文目や3文目の前で改行。短い2文目は同じ行に残す |
| `label-list`                 | 本文の1行に日本語のラベルとコロンが2つ以上 | なし                                                |
| `long-parentheses`           | 日本語を含む括弧内が40字を超える           | なし                                                |
| `sentence-length`            | 日本語を含む文が100字を超える              | なし                                                |
| `ja-no-redundant-expression` | 既存のtextlintルールが冗長な表現を検出する | なし                                                |

独自ルールは本文と箇条書きに適用し、コードブロック、引用、表、先頭のYAMLには適用しない。
コード内の句点やリンク先URLは文章の区切りとして数えない。
リンク文字内のコロンはラベルの検査から除外する。
文の区切りは`sentence-splitter`を使い、引用内の句点などを考慮する。
強調やリンクの内部を分断する改行は、警告だけに留める。

短い2文目が補足かどうか、長い括弧を分けるべきかは書き手が判断する。
条件分岐の表への置き換え、設定例との照合、文書間の重複検査、用語辞書は今回の範囲に含めない。
SKILLのメタデータ検証も別途必要。

## 独自ルールの追加

1. `rules/`にtextlintのルールを書く。
2. [rules.mjs](rules.mjs)にルールと設定を追加する。
3. `tests/`に実際の誤検知や修正時の破損を防ぐ例を追加する。

```sh
npm --prefix scripts/ai-docs test
npm --prefix scripts/ai-docs run check
npm --prefix scripts/ai-docs run format:code
npm --prefix scripts/ai-docs run trial
```

`trial`は既存SKILLを読み、整形前後の警告数と再整形の差分を確認する。ファイルは変更しない。
`check`はBiomeでJavaScriptとJSONの検査・整形済み確認を行い、PrettierでこのディレクトリのMarkdownの書式を確認する。
`format:code`はBiomeの整形と安全な修正をJavaScriptとJSONに適用する。`package-lock.json`は対象外。
CIはルールのテスト、ツール自身の検査と書式、リンク切れを検証する。既存文章の警告は確認用に出力する。
