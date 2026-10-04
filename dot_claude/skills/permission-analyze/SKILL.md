---
name: permission-analyze
description: Claude Code の権限確認・auto モードの拒否・Bash サンドボックスで止まったコマンドを集計し、設定の改善を提案する。「サンドボックスが不便」「権限確認が多い」「permission-analyze」と言われたとき、または週次の定期実行で使う。
---

Claude Code で実際に出た権限確認と auto モードの拒否、サンドボックスで止まったコマンドを集計し、設定の改善候補を出す。対象は Claude Code の確認だけで、Codex 自身の承認は扱わない。

## 手順

1. `python3 ~/.claude/scripts/permission-report.py --days <日数>` を実行する。日数は指定がなければ 7。確認と拒否は `log-permission-event` フックの記録（`~/.local/state/claude/permission-events.jsonl`）から、サンドボックスの失敗は会話記録から集計される。
2. 設定の管理元（`chezmoi source-path ~/.claude/settings.json`）の `permissions`、`autoMode`、`sandbox` を読む。
3. 優先順位を付ける。利用者が不満の具体例を挙げていれば、それを最優先で調べる。それ以外は、再発回数と、取得できる場合はセッションの広がり（確認・拒否のコマンド行の括弧内）で順位を付け、一回限りの操作や一つのセッション内の繰り返しは低くする。
4. 原因ごとに変更先を決める。

| 集計の節 | 原因 | 変更先 |
|---|---|---|
| Permission prompts | ask ルールに一致した（auto モードでも必ず確認になる） | `permissions.ask` から外すか判断する |
| Permission prompts | 副作用が小さいのに毎回確認が出る | `permissions.allow` |
| Auto mode denials by cause and command | 規則名が付いた拒否で、自分のリポジトリ・組織・置き場所が外部扱いされた | `autoMode.environment` |
| Auto mode denials by cause and command | 分類器の利用不可・判定不能（not a settings issue） | 候補にしない |
| Sandbox の各節 | ツールのキャッシュなど、決まった場所への書き込み | `sandbox.filesystem.allowWrite`（`~/` 始まり） |
| Sandbox の各節 | TLS・ソケット・キーチェーン・`ps` など、サンドボックスと相性の悪いツール | `sandbox.excludedCommands`（`cd x && …` のように別のコマンドから始まる形には一致しない） |
| Hosts the sandbox refused | 毎回確認が出る、信頼できる通信先 | `sandbox.network.allowedDomains`（通信先の確認はフックの記録に出ないので、この節で見る。この節は拒否だけを数えるため、空でも確認が無かったとは限らない） |

5. 静的な設定で解決できるものを優先する。CLAUDE.md やプロンプトでの調整は最終手段とし、提案する場合は確実性が低いと明記する。

## 制約

- `~/.ssh`、`~/.aws`、`~/.config/gcloud`、`~/.config/gh`、シェルの起動ファイル、`~/.claude` 配下は `allowWrite` の候補にしない。
- 会話本文やコマンド出力の中身は引用しない。コマンド名、パス、ドメイン、回数だけを書く。
- 定期実行では提案だけにする。設定の変更は、会話で利用者が候補を選んだ場合だけ行う。

## 変更するとき

利用者が候補を選んだら、管理元の `settings.json.tmpl` を編集する。管理元リポジトリの AGENTS.md に従ってテストとコミットを行い、`chezmoi apply ~/.claude/settings.json` で適用し、`chezmoi diff ~/.claude/settings.json` が空であることを確かめる。

## 出力

日本語で短く書く。

- 改善候補：1 行ずつ「追加先キー / 値 / 根拠（回数と、取得できる場合はセッション数）」。無ければ「候補なし」。
- 見送ったもの：多かったが設定では解消しないもの（あれば 1〜3 行）。
- 集計の誤検出が目立つ場合だけ、`chezmoi source-path ~/.claude/scripts/permission-report.py` の直すべき点を 1 行で添える。
