# 実行環境の切り替え

実装はClaude、独立レビューはCodexが担う。
各スキルの完了条件を共通に保ち、実行方法を環境に合わせる。
参照文書内の相対リンクは、その文書のディレクトリを基準に解決する。

## 環境の判定

最初に`harnexus-task environment`を実行し、`environment`を読む。
Cloudでのコマンドの絶対パスは`/workspace/.cloud-setup/bin/harnexus-task`となる。

| 結果           | 進め方                                                                  |
| -------------- | ----------------------------------------------------------------------- |
| `local`        | 各スキルの本文に従う。                                                  |
| `cloud`        | 以下のCloud手順に従う。                                                 |
| `unknown`      | ユーザーに`HARNEXUS_EXECUTION_ENV=cloud\|local`の設定を求めて中断する。 |
| コマンドの失敗 | エラーを報告して中断する。導入方法は「セットアップ」を参照する。        |

## Cloudでの実装

task-orchestrationで対象を選び、task-session-launchとtask-workerは現在のCloudタスクでClaudeを動かす。
Codexは方針判断と結果の確認を担当し、実装や修正をClaudeへ依頼する。

1. [worker.md](../../task-session-launch/references/worker.md)にtask_id・document_refs・completion_targetを埋める。
   プロンプトをワークツリー外の一時ファイルに保存する。
2. 対象のcheckoutで下記の開始コマンドを実行する。
   モデルはユーザーの指定があれば渡し、それ以外は既定を使う。
3. 出力の`sessionId`と`result`を報告する。
   追加指示と修正依頼は、同じ`--session`で再開する。

```sh
harnexus-task claude --session worker-<taskId> --start --prompt-file <FILE> --cwd <checkoutの絶対パス>
harnexus-task claude --session worker-<taskId> --resume --prompt-file <FILE>
```

Claudeの会話を継続する追加指示は、元のCloudタスクへ渡す。
実行が失敗したら、エラーを報告して中断する。
結果不明の場合は、変更内容を確認してからユーザーと復旧方法を決める。
`--recover adopt`は`--resume`と併用し、既存セッションを継続する。
`--recover discard`は未完了の実行記録を破棄する。

## Codexへのレビュー依頼

現在のCloud連携では、別のCodexタスクの起動は引き渡しで行う。

1. 候補をcommitし、`git status`で追跡ファイルの変更が保存済みか確認する。
   `git rev-parse`でbaseとheadのSHAを固定する。
2. [引き渡し依頼](../../task-review-cycle/references/cloud-handoff.md)を埋め、ワークツリー外に保存する。
   ファイル名は`review-handoff-<taskId>-<head短縮>.md`とする。
3. `needs_review`と文書のパスを報告し、独立したCodexによるレビュー結果を待つ。
4. 結果のbase/headを照合し、一致した候補への独立LGTMを完了条件に数える。
   指摘は同じClaude workerへ渡し、修正後のheadで再レビューを依頼する。
   SHAの不一致や判定保留は`needs_review`を維持する。

## Cloudでの通知と定期実行

PR監視と通知はCloud連携の残タスクで、確認には`gh pr view`・`gh pr checks`を使う。
task-workerとpr-watch-linkの報告には「PRは監視されていない（Cloud）」と記載する。
task-dispatchはローカルの台帳とScheduled Taskに依存するため、Cloudでは理由を報告して終了する。

## セットアップ

- harnexusのcheckoutで`bun run install:task:cloud`を実行する。
  実行ファイルは`/workspace/.cloud-setup/bin/harnexus-task`へ配置される。
  Bunの導入方法はスクリプトの案内に従う。
  `expected a subcommand`が出た場合も、この手順で更新する。
  ローカルでの更新は`bun run install:task`を使う。
- Claudeラッパーの導入は`/workspace/.cloud-setup/install.sh`を実行する。
- スキルとHookの導入は`dotctl cloud-install`を使う。
  書き込み先は必要に応じて`--codex-home`・`--claude-home`で指定する。
  出力で移植した設定を確認し、新しいCloudタスクでスキルとHookの読み込みを検証する。
