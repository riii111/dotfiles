---
name: resolve-merge-conflicts
description: |
  Gitの競合を安全に解消し、ターゲットブランチ側の変更が失われていないことまで自己監査する。
  競合した単一PRの解消、長期・まとめブランチへのmain取り込み、既存マージコミットの修正で使う。
---

# resolve-merge-conflicts

競合を解消し、両方の意図した変更が最終結果に残ることを確認してから完了する。ビルドが通ることだけで、ターゲットブランチ側の挙動が保持されたとは判断しない。

## 守ること

- リポジトリの指示を読む。
- 無関係なworktree変更を保持する。
- Git状態を変更する前に、source ref・target ref・merge base・各tipを記録する。
- 明示的な依頼なしに`git reset --hard`、`git checkout --`、force-pushを使わない。
- 競合を解消する依頼では、作業ツリーの競合マーカーを解消してstageする。コミットはユーザーの依頼またはリポジトリの通常フローに従う。
- 動作確認が対象なら、静的検査の後にリポジトリ標準のbuild/testを実行する。

## 手順の選択

1本のfeature branchをtargetへ取り込む、かつ変更範囲が明確なら**単一PR**を使う。

複数PRを積んだブランチ、mainを複数回取り込んだブランチ、main側の変更がすべて残ったかを問う場合は**まとめブランチ**を使う。迷ったらまとめブランチとして扱う。

target側の進行が大きく、独立して検証できるPR・コミット境界がある場合は**段階マージ**を選ぶ。競合を起こした変更または意味のまとまりごとにtargetを取り込んで検証する。相互依存する変更は同じ回に含める。各回で単一PRの手順を繰り返し、最後にまとめブランチの手順5〜7で全体を監査する。

## 共通の準備

1. worktreeがcleanかを確認し、そうでなければ無関係な変更を特定する。
2. 最新のremote refが必要なときだけfetchする。
3. 比較するrefを記録する。

```bash
git status --short
git rev-parse <source> <target>
git merge-base <source> <target>
git log --oneline --decorate <merge-base>..<target>
```

4. 解消前にsourceとtargetの変更を読む。

```bash
git diff --stat <merge-base>...<source>
git diff --stat <merge-base>...<target>
git merge-tree $(git merge-base <source> <target>) <source> <target>
```

`merge-tree`は読み取り専用のプレビューである。行を選ぶ前に、意味的な競合を特定するために使う。

5. まだマージを開始しておらず、開始する依頼なら、baseを表示する競合形式でマージを開始する。

```bash
git -c merge.conflictStyle=zdiff3 merge --no-commit <target>
```

すでに競合状態ならマージを再実行しない。各未解決ファイルはindex stageから読む。`:2`は現在checkoutしているブランチ、`:3`はmerge引数側である。

```bash
git diff --name-only --diff-filter=U
git show :1:<path> # merge base
git show :2:<path> # 現在のブランチ
git show :3:<path> # 取り込む側のブランチ
git log -p <merge-base>..<target> -- <path>
```

## 確認観点

成功経路、エラー種別と秘匿化、観測性、認可、transaction/rollback、並行性・lock、API応答形式、回帰テストを確認する。

## 単一PR

1. PRの意図した変更範囲を`<merge-base>..<source>`として確定する。
2. `git merge-tree`と周辺実装を読み、各競合についてtargetの挙動とPRの意図した差分を両方残す実装を決める。片方を丸ごと採用するのは、他方が確実に後続変更で置換済みな場合だけにする。
3. 競合マーカーを解消して`git add -- <path>`でstageする。すべての競合hunkを周辺文脈とともに確認し、確認観点を満たすよう統合する。
4. 全ファイルをstageしたら、マージコミットを作成またはamendする。続けて`remerge-diff`で自己監査する。

```bash
git show --remerge-diff --format=fuller HEAD
git diff --check HEAD^1..HEAD
```

5. 各remerge hunkについて、base・target parent・source parent・最終結果を比較する。次のいずれかに分類する。
   - 両方の変更を保持
   - API・型変更へ意図的に適応
   - target側の後続変更で置換済み
   - 欠落または巻き戻し
6. PRパッチが黙って失われていないかをファイル単位で検査する。

```bash
scripts/check-patch-survival.sh \
  --base <merge-base> --tip <source>
```

`exact`は未変形で残存、`absent`は未反映候補、`adapted-or-partial`は3-way比較が必要な候補を表す。周辺コードが変わっている場合、パッチ検査だけを証明として扱わない。これは切り分けの手がかりであり、変形されたhunkのレビューに置き換わるものではない。

大量の`exact`出力が不要なら`--nonexact-only`を付ける。

## まとめブランチ

1. target branchをまとめブランチへ取り込んだ全マージを特定し、解消対象または修正対象のマージコミットを選ぶ。
2. 通常、first parentはマージ前にcheckoutしていたまとめブランチ、second parentは取り込んだtargetである。`git show --format=raw <merge>`と各parentの履歴で親順を確認する。
3. `merge-tree`と周辺実装を基に競合を解消し、マージコミットを作成またはamendする。元のマージで競合マーカーが出たファイルだけでなく、main側の変更と重複する全ファイルを統合対象にする。
4. マージコミットに`git show --remerge-diff`を実行する。列挙された全ファイル・全hunkを自己監査する。
5. merge base以降にtarget側へ入ったfirst-parentコミットを古い順に列挙する。squash mergeでは1コミットを1検査単位として扱い、PRマージコミットの存在を前提にしない。各コミットの親との差分を、最終HEADに対してファイル単位で検査する。

```bash
git log --first-parent --reverse --format='%H' <merge-base>..<target>
scripts/check-patch-survival.sh \
  --base <target-commit>^1 --tip <target-commit>
```

各`<target-commit>`に対して繰り返す。出力を基に各ファイルパッチを、完全一致・target内で置換済み・ブランチで適応・未分類に分ける。`exact`以外はすべて3-way比較で調べる。

同じtargetを複数回取り込んだブランチ全体を保証する場合は、各マージコミットについて手順4〜7を繰り返す。各マージのtarget増分を最終HEADに対して検査し、最新の取り込みだけで結論を出さない。

6. まとめブランチとtarget側の両方で変更されたファイル集合を作る。各重複ファイルについて、以下を比較する。

```text
merge base -> branch parent
merge base -> target parent
branch parent + target parent -> final merge result
```

両親それぞれの差分が最終結果に反映されているかを、1ファイルずつ確認する。テキストではなく、確認観点に沿って挙動を確認する。

7. 鮮度は別に確認する。レビュー対象のtarget parentが現在のremote targetより古い場合、後続変更を列挙し、過去の競合解消ミスではなく未取り込みとして報告する。

```bash
git diff --name-only <target-parent>..<target>
```

必要なら後続パッチがHEADへ機械的に適用できるか試す。ただし、それを統合済みの証明とは呼ばない。

`remerge-diff`は一時treeを作る。実行に失敗した場合だけ、Gitが一時objectを作成できる状態か確認する。

## 完了報告

次を簡潔に報告する。

- **対応内容**: 解消した競合と、両方の変更をどう統合したか。
- **自己監査**: 確認したremerge hunk・PRパッチ・重複ファイルの件数、意図的に適応した挙動、実行した・未実行の検査。
- **残る判断**: target側の挙動欠落、未分類の競合結果、未取り込みの後続変更など、AIだけでは完了にできない事項。なければ明記する。

固定したrefと、調査中にworktreeが変わったかを明記する。レビュー対象のマージ親よりtargetが進んでいるなら、target側の全変更が保持されたとは決して言わない。
