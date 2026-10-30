# 実行環境の切り替え

task系スキルの役割・完了条件・レビュー方針は環境によらず同じで、実行方法だけを切り替える。
実装はClaude、独立レビューはCodexが担う。
この分担はCloudでも変えない。
環境判定は各スキルで行わず、`harnexus-task environment`に任せる。
スキルを複製しない。
参照文書内の相対リンクは、その文書のディレクトリを基準に解決する。

## 判定

手順の最初に`harnexus-task environment`を実行し、`environment`を読む。
Cloudで`PATH`にない場合は絶対パス`/workspace/.cloud-setup/bin/harnexus-task`を使う（導入は下の「前提」）。

- `local`：各スキルの本文どおりに進める。
- `cloud`：このファイルの「Cloud」に従う。
- `unknown`：停止する。
  `HARNEXUS_EXECUTION_ENV=cloud|local`の設定をユーザーに求める。
- コマンドがない・失敗する：停止し、その出力を報告する。
  `expected a subcommand`は導入済みの`harnexus-task`が古いため、harnexusのチェックアウトで`bun run install:task`（Cloudでは`install:task:cloud`）の実行を求める。

`HARNEXUS_EXECUTION_ENV`があれば最優先で、cloud/local以外の値はエラーになる。
`CODEX_ENVIRONMENT_ID`が空でなければcloudと見なすが、公式に保証された変数ではなく観測された値である。
変数がないことだけではlocalと判断されず、harnexusの呼び出しソケットへ実際に接続できたときだけlocalになる。

## Cloud

Cloudでは他のタスクやスレッドを作成・再開できない。
次のコマンドはCloudで明示エラーになる：`launch`・`review`・`resolve`・`name`・`watch`・`state --request`。
エラーを避ける回避や、成功したことにする記録はしない。

| スキル              | Cloudでの扱い                                                                                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| task-session-launch | 別タスクは作らず、現在のCloudタスク内でClaude workerを起動する（下の「Claude workerの起動」）。                                                                                         |
| task-worker         | 実装はClaudeが行う。実行主体がCodexなら自分で実装せず、Claude workerへ委任する。PRの監視登録（`harnexus-task name`）は行わず、完了報告の冒頭に「PRは監視されていない（Cloud）」と書く。 |
| task-review-cycle   | Claudeによるレビューで代替しない。「独立レビューの引き渡し」に従い、独立LGTMがなければ`needs_review`で止める。                                                                          |
| pr-watch-link       | 登録しない。「PRは監視されていない（Cloudは通知未対応）」と伝え、`gh pr view`・`gh pr checks`で確認するようユーザーに求める。                                                           |
| task-dispatch       | 実行しない。`~/agent-desk/`の台帳とScheduled TaskはローカルのCodex Appに依存すると報告する。                                                                                            |
| task-orchestration  | 開始対象の選定までは行える。起動はtask-session-launchの扱いに従う。                                                                                                                     |

### Claude workerの起動

1. [worker.md](../../task-session-launch/references/worker.md)の項目（task_id・document_refs・completion_target）を依頼の値で埋めたプロンプトを、ワークツリー外の一時ファイルに書く。
2. このcheckoutで下記のコマンドを実行する。
   モデルの指定がなければ既定に任せる。
3. 出力の`sessionId`と`result`を報告する。
   続きの指示や修正の依頼は、同じ`--session`で`--resume`を使う。
4. Codexは実装を代行しない。
   workerの結果が不足なら、`--resume`で不足を指示する。

```sh
harnexus-task claude --session worker-<taskId> --start --prompt-file <FILE> --cwd <checkoutの絶対パス>
```

終了コード、`Not logged in`、ネットワーク未許可などの失敗は出力の理由を報告して止める。
結果不明（`did not report back`）は再実行せず、ユーザーに確認を求める。
復旧は`--recover adopt`（`--resume`と併用）か`--recover discard`で、変更の有無を確認してから使う。
`claude-cloud`がなければ`/workspace/.cloud-setup/install.sh`の実行を求める。
セッションはこのタスクのファイルシステムにあり、新しいCloudタスクへは引き継がれない。

### 独立レビューの引き渡し

CloudにはCodexの別タスクや独立コンテキストを自動で起動する手段がない。
そのためレビューは引き渡しで行い、自動でLGTMにしない。

1. 候補をcommitし、追跡ファイルに未commitの変更がないことを`git status`で確認する。
   baseとheadのSHAを`git rev-parse`で固定する。
2. [引き渡し依頼](../../task-review-cycle/references/cloud-handoff.md)の項目を埋めた文書を、ワークツリー外に`review-handoff-<taskId>-<head短縮>.md`として保存する。
3. 状態を`needs_review`として報告し、停止する。
   報告には文書のパスと、Codexの別タスクまたは独立コンテキストへ渡す必要があることを書く。
4. ユーザーまたは別のCodexが返したレビュー結果を受け取ったら、結果のbase/headが固定したSHAと一致することを確認する。
   不一致・LGTMなし・判定保留は完了にせず、指摘があれば同じClaude workerへ`--resume`で修正を依頼し、新しいheadで手順1からやり直す。
5. 完了条件（task-workerの定義）のうち独立LGTMは、この手順で得たものだけを数える。
   Claudeによる自己レビューやこのタスク内の確認はLGTMとして数えない。

## 前提

- Cloudには`harnexus-task`の導入が別途必要で、自動では入らない。
  harnexusのチェックアウトで`bun run install:task:cloud`を実行する。
  `bash scripts/install-cloud-task.sh`でも導入できる。
  導入先は`/workspace/.cloud-setup/bin/harnexus-task`となる。
  `PATH`は変更されないため、絶対パスで呼ぶ。
  Bunがなければ、スクリプトが導入コマンドを表示する。
- スキルとHookは`dotctl cloud-install`で導入する。
  `$CODEX_HOME`が読み取り専用なら、書き込める場所を`--codex-home`・`--claude-home`で明示する。
  Cloudがそれらを自動で読み込むかは確認していない。
- ローカルのHookと通知はCloudへ自動では移らない。
  移したものと移していないものは`dotctl cloud-install`の出力に出る。
