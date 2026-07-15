---
name: rust-worktree-storage-triage
description: Rust の複数 worktree を並列開発する macOS で、容量不足を調査・解消する。Nix store、Rust の target とエディタ用ビルド成果物、sccache、Docker/Colima、アプリのデータを分類し、再生成可能なものから安全に削除する必要があるときに使う。
---

# Rust Worktree 容量調査

容量を大きい順に測定し、対象を「再生成可能な成果物」「稼働中の開発状態」「永続データ」に分ける。削除前に必ず利用状況を確認し、解放量と再発原因を報告する。

## 調査

1. システム領域とデータ領域の空き容量を確認する。

```sh
df -h /
df -h /System/Volumes/Data
```

2. 容量を使う候補を測る。ホームディレクトリ、`/nix/store`、各 worktree、アプリデータを対象にする。大きい場所だけを一段深掘りする。

```sh
du -h -d1 ~ 2>/dev/null | sort -rh | head -20
du -sh /nix/store ~/.rustup ~/.cargo/registry ~/Library/Application\ Support ~/Library/Caches 2>/dev/null
fd -t d '^target$' <worktree-root> --hidden --no-ignore --exclude .git -x du -sh {}
```

3. Rust の成果物は `target` だけでなく、`.nvim/target` など隠しディレクトリも確認する。`rust-analyzer`、`cargo`、`rustc`、`sccache` が動いている worktree は稼働中として扱う。

```sh
pgrep -fl 'rust-analyzer|cargo|rustc|sccache'
rustup toolchain list
sccache --show-stats
```

4. Nix は古い世代と到達不能な store path を分けて確認する。世代削除はロールバックを放棄するため、保持期間を確認する。dry-run の容量は見込みとして扱う。

```sh
nix-collect-garbage --delete-older-than 30d --dry-run
sudo nix-collect-garbage --delete-older-than 30d --dry-run
nix store gc --dry-run
```

上から順に user profile、system profile、世代を残したままの store GC を確認する。`nix-collect-garbage --delete-older-than` は世代削除と GC を一括で行う。

5. Docker/Colima は仮想ディスクを直接削除しない。稼働中のコンテナと再利用可能なイメージを確認する。

```sh
docker ps
docker system df
```

## 分類と対処

| 対象 | 判断 | 対処 |
| --- | --- | --- |
| Nix の GC 候補 | 世代を保持したまま到達不能な store path を消す | `nix store gc` を実行する |
| Nix の古い世代 | 削除した世代へはロールバックできない | `nix-collect-garbage --delete-older-than <期間>` を使う |
| 停止中 worktree の `target` | 再コンパイル可能 | worktree 単位で削除する |
| 稼働中の `target`、`.nvim/target` | 開発中の解析・ビルドに使う | 原則残す。必要なら対象を明示して削除する |
| 古い Rust toolchain | default・active でなく、必要な project からも参照されない | `rustup toolchain uninstall <toolchain>` を使う |
| sccache | `sccache --show-stats` が示すキャッシュディレクトリ | サーバー停止後にキャッシュを削除する。`SCCACHE_CACHE_SIZE` で上限を下げる |
| Cargo registry、Go・パッケージ管理のキャッシュ | 再ダウンロード可能 | 使用中プロセスを止めてから消去する |
| 未使用 Docker イメージ | dangling image は安全寄り。未参照イメージには再取得できないものがある | まず `docker image prune` を使う。`-a` は対象一覧と再取得可否を確認してから使う |
| Colima の仮想ディスク | コンテナ・ボリューム・イメージを含む | 初期化は最後の手段 |
| アプリのキャッシュ | 再生成可能な一時データ | アプリ終了後に対象を限定して削除する |
| アプリの VM bundle、データベース、チャット履歴 | 機能状態や利用者データを含みうる | 用途と再生成コストを確認してから扱う |

Colima の prune 後は `du -sh ~/.colima ~/.config/colima 2>/dev/null` でホスト側の実サイズを測る。縮まなければ稼働中の Colima に `colima ssh -- sudo fstrim -a` を試す。

### APFS ローカルスナップショット

削除後も空き容量が増えない場合だけ確認する。`tmutil thinlocalsnapshots` は Time Machine のローカル復元ポイントを失わせるため、この skill では実行しない。影響を説明してコマンドを提示し、利用者に実行してもらう。

```sh
tmutil listlocalsnapshots /
tmutil thinlocalsnapshots / <bytes> 4
```

削除操作は、対象・概算容量・再生成の有無を伝え、利用者が許可した範囲だけで実行する。

## 再発防止

Nix が大きな原因なら、nix-darwin の自動 GC と store 最適化を有効にし、保持期間が運用方針に合うか確認する。緊急時は世代削除後に GC し、必要なら `nix store optimise` を実行する。

worktree は削除時に対応する `target` と隠しエディタ用成果物を残さない。頻繁に使う worktree は成果物を残し、休眠 worktree を優先して掃除する。sccache は容量上限を開発環境に合わせて設定する。`cargo clean` は共有キャッシュではなく現在の worktree のビルド成果物を消すため、容量逼迫時の第一選択にはしない。

その他の候補として、Homebrew、npm/pnpm/uv のキャッシュ、ゴミ箱、Xcode の開発データも確認する。

## 報告

次を短くまとめる。

- 空き容量の前後
- 大きかった場所と解放量
- 残したものと理由
- 自動化すべき再発原因
