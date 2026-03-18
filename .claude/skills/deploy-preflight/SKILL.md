---
name: deploy-preflight
description: |
  STG デプロイ前のプリフライトチェック。コンフリクト検出、意図しない変更の検出、Flyway migration 衝突チェックを行う。
  トリガー: (1) STGにデプロイしたい, (2) デプロイ前チェック, (3) deploy preflight, (4) リリース前確認
user_invocable: true
---

# Deploy Preflight Check

STG 環境へデプロイする前に、安全性を確認するプリフライトチェックを実行する。

## 前提知識

- STG デプロイフロー: `memo/knowledge/deploy/stg-release-flow.md`
- Flyway checksum mismatch の教訓: `~/.claude/cache/learnings/contract-one/flyway-checksum-mismatch-deploy-stg.md`
- マージ方向の教訓: `~/.claude/cache/learnings/contract-one/deploy-branch-merge-direction.md`

## 入力

ユーザーに以下を確認する（省略時はデフォルトを使う）:

- **デプロイ対象ブランチ**: `git branch --show-current` で表示して確認
- **ベースブランチ**: デフォルト `origin/master`

## チェック手順

### Step 1: 最新の deploy-stg ブランチを特定

```bash
git fetch origin
git branch -r | rg 'origin/deploy-stg/' | sort | tail -3
```

最新の `deploy-stg/<date>` を以降のチェックで使用する。

### Step 2: コンフリクトチェック（merge-tree）

Working tree を汚さずにドライランマージを実行:

```bash
git merge-tree --write-tree origin/deploy-stg/<date> <feature-branch>
```

- ハッシュのみ出力 = コンフリクトなし
- `CONFLICT` を含む出力 = コンフリクトあり → 内容を報告

### Step 3: 意図しない変更の検出

ユーザーの意図する変更と、実際に deploy-stg にマージされる変更を比較する。

```bash
# ユーザーの意図する変更ファイル一覧
git diff <base-branch>...<feature-branch> --name-only | sort > /tmp/intended.txt

# deploy-stg にマージされる変更ファイル一覧
git diff origin/deploy-stg/<date>...<feature-branch> --name-only | sort > /tmp/actual.txt

# actual にだけあるファイル = 意図しない変更の可能性
comm -13 /tmp/intended.txt /tmp/actual.txt
```

- **差分ゼロ**: 合格。意図した変更のみがデプロイされる
- **差分あり**: 該当ファイルを報告し、ユーザーに判断を仰ぐ
  - deploy-stg 上で他の人が同じファイルを変更していて、マージ結果に影響する可能性がある

### Step 4: Flyway migration 衝突チェック

現在のブランチに migration ファイルの差分があるか確認:

```bash
git diff <base-branch>...<feature-branch> --name-only -- backend/database/src/main/resources/db/
```

- **差分なし**: migration なし → Flyway リスクなし。チェック完了
- **差分あり**: 以下を実行
  1. 追加された migration のバージョン番号を抽出
  2. `find-migration` コマンド（ユーザーの .zshrc に定義済み）で deploy-stg ブランチとの衝突を確認:
     ```bash
     find-migration <VERSION>
     # 例: find-migration V0524
     ```
  3. 衝突がある場合は `stg-release-flow.md` の「既知の落とし穴」セクションの対処法を案内

### Step 5: 結果サマリー

以下の形式で報告:

| チェック項目 | 結果 |
|-------------|------|
| コンフリクト（merge-tree） | OK / NG |
| 意図しない変更 | なし / 要確認（N件） |
| Migration 衝突 | なし / 要対応 |

全項目 OK であれば「プリフライトチェック合格」と報告する。

## 注意事項

- deploy-stg を feature ブランチにマージしてはいけない（逆方向のみ OK）
- 実際のデプロイ（Slack コマンド `/stg-release`）はユーザーが手動で行う
- このスキルはチェックのみ。破壊的操作は一切行わない
