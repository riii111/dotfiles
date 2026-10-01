---
name: sandbox-review
description: Claude Code の Bash サンドボックスで止まったコマンドを会話記録から集計し、sandbox 設定の改善を提案する。「サンドボックスが不便」「権限確認が多い」「sandbox-review」と言われたとき、または週次の定期実行で使う。
---

会話記録から、サンドボックスのせいで作業が止まった箇所を集計し、設定の改善候補を出す。

## 前提

- 設定の管理元は chezmoi の `settings.json.tmpl`。場所は `chezmoi source-path ~/.claude/settings.json` で調べる。
- サンドボックス内のコマンドは、作業ディレクトリと一時ディレクトリにしか書き込めない。新しいドメインへの通信は確認になる。
- 外へ書き込むコマンドは一度失敗し、`dangerouslyDisableSandbox: true` でやり直す。やり直しは 1 往復の無駄で、許可リストに無いコマンドなら確認も出る。
- `excludedCommands` のコマンドはサンドボックスの外で動き、`permissions` の許可判定を受ける。`git -C <外のパス>` や `cd x && git …` のように別のコマンドから始まる形は、除外に一致しない。

## 手順

1. `python3 ~/.claude/scripts/sandbox-report.py --days <日数>` を実行する。日数は指定がなければ 7。
2. 管理元の `sandbox` と `permissions` を読む。
3. 回数の多いものから、次のどれで解消できるかを判断する。
   - `sandbox.filesystem.allowWrite`：ツールのキャッシュなど、決まった場所への書き込み。パスは `~/` 始まりで書く。
   - `sandbox.excludedCommands`：TLS、ソケット、キーチェーンを使うなど、サンドボックスと相性の悪いツール。
   - `sandbox.network.allowedDomains`：毎回確認が出る、信頼できるドメイン。
   - `permissions.allow`：除外したコマンドのうち、毎回確認が出る副作用の小さいもの。
   - 設定では解消しない：一回限りの作業ディレクトリ外への操作、調査中の誤検出。
4. 回数が 2 回未満のものや、1 セッションに偏っているものは候補にしない。
5. 利用者が不満の具体例を挙げていれば、集計よりその例を優先して原因を調べる。

## 制約

- `~/.ssh`、`~/.aws`、`~/.config/gcloud`、`~/.config/gh`、シェルの起動ファイル、`~/.claude` 配下は `allowWrite` の候補にしない。
- 会話本文やコマンド出力の中身は引用しない。コマンド名、パス、ドメイン、回数だけを書く。
- 定期実行では提案だけにする。設定の変更は、会話で利用者が候補を選んだ場合だけ行う。

## 変更するとき

利用者が候補を選んだら、管理元の `settings.json.tmpl` を編集する。管理元リポジトリの AGENTS.md に従ってテストとコミットを行い、`chezmoi apply ~/.claude/settings.json` で適用し、`chezmoi diff ~/.claude/settings.json` が空であることを確かめる。

## 出力

日本語で短く書く。

- 改善候補：1 行ずつ「追加先キー / 値 / 根拠（回数）」。無ければ「候補なし」。
- 見送ったもの：多かったが設定では解消しないもの（あれば 1〜3 行）。
- 集計の誤検出が目立つ場合だけ、`chezmoi source-path ~/.claude/scripts/sandbox-report.py` の直すべき点を 1 行で添える。
