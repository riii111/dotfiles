# Cloud 開発環境

`dot_codex/skills` と `.chezmoitemplates/agents-common.md` を共通の配布元とする。Cloud では同じ dotfiles commit を用意し、各セットアップを実行する。CLI の commit はセットアップの `HARNEXUS_CREW_REV` で固定する。

| 環境 | SKILL と開発ルール | CLI と hook |
| --- | --- | --- |
| ローカル | chezmoi で `~/.codex/skills` と `~/.codex/AGENTS.md` に適用 | Nix と chezmoi の管理対象を使う |
| Claude Code Cloud | `scripts/cloud-setup.sh` が `~/.claude/skills` と `~/.claude/CLAUDE.md` に配置 | 同スクリプトが CLI と `~/.claude/settings.json` の hook を用意し、SessionStart で更新する |
| Codex Cloud | `scripts/codex-cloud-setup.sh <対象リポジトリ>` が `.agents/skills` と `~/.codex/AGENTS.md` に配置 | 同スクリプトが CLI と `~/.codex/hooks.json` を用意する。生成設定が Cloud で読み込まれるかは未確認 |

Cloud のセットアップには Linux x86_64、Git、Python、hook ビルド用のネットワークが必要。CLI を設置する `~/.local/bin` を Cloud の PATH に含める。Codex の初回セットアップは既存の同名 SKILL、`task.json`、`hooks.json`、`AGENTS.md`、hook 本体があるか、CLI の版が異なるか不明なら停止する。新しい環境で実行し、セットアップが表示する dotfiles commit と CLI commit を記録する。`-dirty` は未コミット変更を含むことを示す。対象リポジトリに生成された SKILL は未追跡ファイルになるため、成果に含める前に確認する。

```sh
HARNEXUS_CREW_TOOLCHAIN=moon HARNEXUS_CREW_REV=<公開済みのCLIコミット> bash <dotfiles>/scripts/codex-cloud-setup.sh <対象リポジトリ>
```

`moon` 版の CLI は、固定された MoonBit を PATH に用意するか、Nix で CLI リポジトリの開発環境を利用できる必要がある。旧 Bun 版には Codex Cloud の独立レビュー経路がない。CLI の変更を公開するまでは上記のコミットを取得できない。Claude Code Cloud で新 CLI を使う場合も `HARNEXUS_CREW_TOOLCHAIN=moon` と同じ commit を指定する。Codex の更新や再開時の既存設定への安全な切り替えは未対応であり、更新には新しい環境が必要。

Claude Code Cloud の Harnexus チャットで選んだ SKILL は、Cloud 側の `~/.claude/skills/<名前>/SKILL.md` に解決する。配置されていない名前は Cloud 側で読めない。Codex Cloud は `.agents/skills` を利用するが、セットアップ後に作った SKILL が同じセッションの選択欄と明示呼び出しに反映されるかは未確認。

## 実環境での確認

使い捨ての Cloud 環境で、対象コミットと製品・CLI の版を記録する。実環境の hook 発火と、判定バイナリを直接呼んだ結果は別に記録する。

1. hook の一時的な観測用ラッパーを用意し、イベント名と判定のみを保存して元の `agent-hooks` に入力を渡す。入力本文や環境変数は保存しない。設定を作業用環境に限ってラッパーへ向け、製品の仕様に従い hook を読み直す。
2. 一時 Git リポジトリで `git status --short` を実行し、PreToolUse が発火して処理が通ることを確認する。存在しないファイルへの `git add -f` を実行し、hook の拒否を確認する。hook が動かなくても対象ファイルやリモートに変更が生じない条件にする。
3. Codex の PermissionRequest は承認が必要な操作でのみ発火する。信頼済みの一時 checkout で `git status --short` を承認要求付きで実行し、イベントと許可を観測する。通常の実行でイベントが出ないことも区別する。承認経路がない環境では未検証と記録する。
4. 新規・再開した各 Cloud で `task-worker` と `task-review-cycle` の本文、参照ファイル、`harnexus-crew` の commit を確かめ、固定 base/head の独立レビューと結果返却を実行する。Claude の選択 SKILL と Codex の選択欄・明示呼び出しも確認する。

Cloud のネイティブ hook 発火、PermissionRequest、選択 SKILL の解決、独立レビューの実 Cloud 完走は未確認。Codex の設定を生成できたことだけで必須の制限が発火するとは判定しない。
