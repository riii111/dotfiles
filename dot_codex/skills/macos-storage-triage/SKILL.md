---
name: macos-storage-triage
description: macOS の不要データと容量不足を調査・解消する。Nix、Rust のビルド成果物、Docker/Colima、Homebrew、アプリのデータを分類し、再生成可能なものから安全に削除する必要があるときに使う。
---

# macOS ストレージ整理

容量を大きい順に測定し、対象を「再生成可能」「稼働中」「永続データ」「未確認」に分ける。削除は利用者が対象・概算容量・再生成の有無を確認した後だけにする。

## 調査

まず読み取り専用の収集を実行する。引数は調べる Rust worktree の親ディレクトリで、省略時はカレントディレクトリを調べる。

```sh
scripts/inspect.sh <worktree-root> > storage.tsv
```

詳細調査では次を使う。

```sh
scripts/inspect.sh --with-deep-sizes --with-nix-dry-run <worktree-root> > storage.tsv
```

TSV の `status` は `observed`、`absent`、`rebuildable_needs_confirmation`、`running_hold`、`persistent_hold`、`unverified` を使う。`unverified` は権限不足、コマンド不在、調査失敗、意図的な未実行を表す。容量ゼロとして扱わない。長いコマンド出力は元のバイト数、先頭、末尾を明示して記録する。

`--with-deep-sizes` は `/nix/store`、アプリデータ、キャッシュの全走査を有効にする。`--with-nix-dry-run` は時間のかかる user profile の Nix dry-run を有効にする。system profile の dry-run は `sudo` が必要なため、スクリプトでは未確認として記録する。

### 容量と Rust

```sh
df -h /
df -h /System/Volumes/Data
du -h -d1 ~ | sort -rh | head -20
fd -a -t f '^Cargo\.toml$' <worktree-root> --hidden --no-ignore --exclude .git
fd -a -t f '^(rust-toolchain|rust-toolchain\.toml)$' <worktree-root> --hidden --no-ignore --exclude .git
pgrep -l '^(rust-analyzer|cargo|rustc|sccache)$'
rustup toolchain list
rustup override list
rustup show active-toolchain
sccache --show-stats
```

`target` と `.nvim/target` は、`Cargo.toml` がある Git worktree 内の候補だけを扱う。Rust プロセスの PID と cwd を worktree に照合し、照合不能なら `running_hold` として残す。時刻はビルド時刻ではなくディレクトリの更新時刻として扱う。

Rust toolchain を消すときは、`rust-toolchain.toml` と override を調べ、残す版を決め、先に `rustup default <残すtoolchain>` を実行する。その後に active/default でない版だけを削除する。検証は `rustup toolchain list`、`rustup override list`、`rustup run <残すtoolchain> rustc --version` に留め、`cargo check` のような再取得を起こしうる操作をしない。

### Nix

Nix の結果はマシン全体の候補であり、特定の worktree やプロジェクトの容量ではない。世代削除はロールバックを放棄する。dry-run の容量は見込みで、コマンドが失敗した場合は容量を確定値として報告しない。

```sh
nix-collect-garbage --delete-older-than 30d --dry-run
sudo nix-collect-garbage --delete-older-than 30d --dry-run
nix store gc --dry-run
```

上から user profile、system profile、世代を残したままの store GC を調べる。`nix-collect-garbage --delete-older-than` は世代削除と GC を一括で行う。

### Docker、Colima、Homebrew

```sh
docker ps
docker system df
brew cleanup --dry-run
brew autoremove --dry-run
brew --cache
```

Docker は `docker image prune` を先に使う。`-a` は対象一覧と再取得可否を確認してからにする。Colima の prune 後は `du -sh ~/.colima ~/.config/colima` でホスト側を再測定し、縮まなければ `colima ssh -- sudo fstrim -a` を試す。仮想ディスクの初期化は最後の手段にする。

Homebrew は dry-run の候補、autoremove 候補、download cache を独立して報告する。`brew` がない場合は `unverified` とする。

## 分類と対処

| 対象 | 分類 | 対処 |
| --- | --- | --- |
| Nix の GC 候補 | 再生成可能だが確認が必要 | `nix store gc` を使う |
| Nix の古い世代 | ロールバック不能 | 保持期間を確認してから `nix-collect-garbage --delete-older-than <期間>` を使う |
| 停止中 worktree の `target` | 再生成可能だが確認が必要 | worktree 単位で削除する |
| 稼働中の `target`、`.nvim/target` | 稼働中のため保留 | 原則残す |
| 古い Rust toolchain | 再生成可能だが確認が必要 | default/override/active を確認してから `rustup toolchain uninstall <toolchain>` を使う |
| sccache、Cargo registry、Homebrew cache | 再生成可能だが確認が必要 | 使用中プロセスを止め、対象を限定して削除する |
| 未使用 Docker イメージ | 再生成可能だが確認が必要 | dangling image を先に削除する |
| Colima の仮想ディスク、アプリの VM bundle、データベース、チャット履歴 | 永続データのため保留 | 用途と再生成コストを確認する |
| 権限不足・コマンド不在・調査失敗 | 未確認 | 容量を推測せず、必要な権限または代替手段を報告する |

### APFS ローカルスナップショット

削除後も空き容量が増えない場合だけ確認する。`tmutil thinlocalsnapshots` は Time Machine のローカル復元ポイントを失わせるため、この skill では実行しない。影響を説明してコマンドを提示し、利用者に実行してもらう。

```sh
tmutil listlocalsnapshots /
tmutil thinlocalsnapshots / <bytes> 4
```

## 報告と再発防止

調査、分類、削除候補の提示、利用者確認、対象限定削除、空き容量の再測定、再発防止提案の順に進める。最終提示では `bytes` が数値の行を容量の大きい順に並べ、容量なしの行と `unverified` は別に報告する。報告には空き容量の前後、大きかった場所と解放量、残したものと理由、未確認領域、自動化すべき再発原因を含める。

Nix が大きな原因なら、nix-darwin の自動 GC と store 最適化、保持期間を見直す。worktree は削除時に対応する `target` と隠しエディタ用成果物を残さない。sccache は容量上限を開発環境に合わせて設定する。その他の候補として npm/pnpm/uv のキャッシュ、ゴミ箱、Xcode の開発データも確認する。
