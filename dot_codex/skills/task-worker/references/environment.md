# 実行環境の切り替え

task系スキルの役割・完了条件・レビュー方針は環境によらず同じで、実行方法だけを切り替える。
環境判定は各スキルで行わず、`harnexus-task environment`に任せる。
スキルを複製しない。

## 判定

手順の最初に`harnexus-task environment`を一度実行し、`environment`を読む。

- `local`：各スキルの本文どおりに進める。
- `cloud`：このファイルの「Cloud」に従う。
- `unknown`：停止する。
  `HARNEXUS_EXECUTION_ENV=cloud|local`の設定をユーザーに求める。
- コマンドがない・失敗する：停止し、その出力を報告する。
  `expected a subcommand`は導入済みの`harnexus-task`が古いため、harnexusのチェックアウトで`bun run install:task`の実行を求める。
  Cloudでの導入は下の「前提」を参照。

`HARNEXUS_EXECUTION_ENV`があれば最優先で、cloud/local以外の値はエラーになる。
`CODEX_ENVIRONMENT_ID`が空でなければcloudと見なすが、公式に保証された変数ではなく観測された値である。
変数がないことだけではlocalと判断されず、harnexusの呼び出しソケットへ実際に接続できたときだけlocalになる。

## Cloud

Cloudでは他のタスクやスレッドを作成・再開できない。
次のコマンドはCloudで明示エラーになる：`launch`・`review`・`resolve`・`name`・`watch`・`state --request`。
エラーを避ける回避や、成功したことにする記録はしない。

| スキル | Cloudでの扱い |
| --- | --- |
| task-session-launch | 実行しない。workerを別タスクとして作れないと報告し、ユーザーに新規Cloudタスクを手動で作り同じ依頼を渡すよう求める。 |
| task-worker | このタスクで実装する。PRの監視登録（`harnexus-task name`）は行わず、完了報告の冒頭に「PRは監視されていない（Cloud）」と書く。 |
| task-review-cycle | 下の「Cloudでのレビュー」に従う。 |
| pr-watch-link | 登録しない。「PRは監視されていない（Cloudは通知未対応）」と伝え、`gh pr view`・`gh pr checks`で確認するようユーザーに求める。 |
| task-dispatch | 実行しない。`~/agent-desk/`の台帳とScheduled TaskはローカルのCodex Appに依存すると報告する。 |
| task-orchestration | 開始対象の選定までは行える。起動はtask-session-launchの扱いに従い、起動できない対象を報告する。 |

### Cloudでのレビュー

独立レビューは、このタスク内で新しいコンテキストのClaudeを動かして行う。
別のCloudタスクではないため、独立性はローカルのreview Taskより弱い。
完了報告に「同一タスク内のClaudeによるレビュー」と書く。

1. 候補をcommitし、追跡ファイルに未commitの変更がないことを`git status`で確認する。
   baseとheadのSHAを`git rev-parse`で固定する。
2. [reviewer.md](../../task-review-cycle/references/reviewer.md)の項目をこのcheckoutの値で埋めたプロンプトを、ワークツリー外の一時ファイルに書く。
   reviewerは変更を加えないため、このコマンドの`--permission-mode plan`を使う。
3. 初回は`harnexus-task claude --session review-<taskId> --start --prompt-file <FILE> --permission-mode plan`を実行する。
   修正後の新しいheadには、同じ`--session`で`--resume`を使う。
   同じheadは再送しない。
4. 出力の`result`を読み、base/headが固定したSHAと一致することを確認してから判定する。
5. 失敗（終了コード、`not logged in`、ネットワーク未許可など）は偽のLGTMにせず、出力の理由を報告して停止する。
   `claude-cloud`がなければ`/workspace/.cloud-setup/install.sh`の実行をユーザーに求める。

状態は`harnexus-task claude --session <名前>`で見られる。
セッションはこのタスクのファイルシステムにあり、新しいCloudタスクへは引き継がれない。

## 前提

- Cloudには`harnexus-task`の導入が別途必要で、自動では入らない。
  harnexusのチェックアウトとBunがあれば、`bun --no-env-file --config=/dev/null <checkout>/src/bootstrap/task/main.ts`を`harnexus-task`として呼べる。
- スキルとHookは`dotctl cloud-install`で導入する。
  Cloudがそれらを自動で読み込むかは確認していない。
- ローカルのHookと通知はCloudへ自動では移らない。移したものと移していないものは`dotctl cloud-install`の出力に出る。
