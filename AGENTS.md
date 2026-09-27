# dotfiles の作業規約

- chezmoi の管理元を編集し、適用は変更対象に限定する。適用後は実ファイルと `chezmoi diff` を確認する。
- 変更後は `nix develop -c ./bin/executable_dotctl test` を実行する。文書のみの変更では不要。
- PR 本文は目的を短い箇条書きで示す。検証セクションは付けない。

## 依存関係の更新

- Nix・Neovim の更新は Draft PR を作り、Ready for review で CI を起動する。マージとローカル適用は手動とする。
- プラグイン実行ジョブは読み取り専用を維持する。書き込みジョブでは lockfile・収集情報を未信頼データとして検証し、既定ブランチのスクリプトで本文を生成する。
- Actions の SHA 固定と `persist-credentials: false` を維持し、PAT は使わない。
- レビューは lockfile 差分とコミット SHA を基準にする。compare リンクのリポジトリ名やバージョン等の収集情報は参考値で、コミットメッセージなど上流の自由文は本文に含めない。
- lockfile 外の取得・実行も確認する：blink.cmp のリリースバイナリ、telescope-fzf-native の `make`、Mason の未固定ツール、Nix インストーラ本体の実行時取得。
- ローカルの `scripts/nvim-plugins.py` は利用者権限で上流コードを実行する。一時 XDG ディレクトリはサンドボックスではない。更新確認には Actions の `Neovim Verify` の `update` 入力を利用できる。
- 更新適用は `chezmoi apply ~/.config/nvim/lazy-lock.json` 後に `nvim --headless '+Lazy! restore' +qa`。ロールバックも先に lockfile を戻し、同じ手順を使う。
- lockfile に変更がない月は PR を作らない。制約外の新版情報は Actions の Step Summary で確認する。
