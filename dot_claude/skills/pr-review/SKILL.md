---
name: pr-review
description: >
  PRレビューを実施するスキル。他者のPRにも自分のPRにも使える。
  "PRレビュー", "PR review", "レビューして", "review PR", "review pull request",
  PR URLが渡された場合に使用する。
  subagentによる並列レビュー、Codex/CodeRabbit連携、worktreeベースの安全なコード調査を行う。
---

# PR Review Skill

PRの変更内容を多角的にレビューし、ファイル・行レベルの指摘を生成するスキル。

## 前提条件

- `gh` CLI が認証済みであること
- `git` が利用可能であること
- 外部ツール使用時は `codex` CLI, `coderabbit` CLI が利用可能であること（なければスキップ）

## 実行フロー概要

```
Phase 0: Worktree準備（スクリプト）
Phase 1: Auto-analysis + ユーザー確認
Phase 2: 外部ツールスキャン（スクリプト。ユーザー選択時のみ。全モードで利用可）
Phase 3: レビュー実行（Quick: main agent / Standard・Deep: subagent並列）
Phase 4: 検証・統合・出力（Standard: スポットチェック / Deep: 検証agent）
Phase 5: 完了報告
```

---

## Phase 0: Worktree準備

スクリプトを実行してworktreeとレビューディレクトリを準備する。

```bash
source_output=$(bash scripts/pr-review-setup.sh "$PR_NUMBER")
eval "$source_output"
# → WORKTREE_DIR, REVIEW_DIR, PR_BRANCH, BASE_BRANCH が設定される
```

以降、すべてのコード調査は `$WORKTREE_DIR` 配下で行う。
subagent起動時も、このパスをCWDとして指定すること。

---

## Phase 1: Auto-analysis + ユーザー確認

### 1-1. Auto-analysis

PRのメタデータを取得し、規模を自動判定する。
additions/deletions/changedFiles は `gh pr view` のJSON出力から取得する。
`gh pr diff` に `--stat` オプションは存在しないので使用しないこと。

```bash
gh pr view "$PR_NUMBER" --json title,body,baseRefName,headRefName,additions,deletions,changedFiles
gh pr diff "$PR_NUMBER" --name-only
```

### 1-2. ユーザーへの確認（AskQuestion）

**必ず** AskUserQuestion で以下を確認する。スキップしてはならない。

確認事項:

1. **レビューモード**: Quick / Standard / Deep
2. **外部ツール（Codex/CodeRabbit）を使う**: する / しない
3. **追加コンテキスト**: なし / ファイルパス指定 / この場で貼り付け
4. **特に注力したい観点**（自由記述、任意）

コンテキスト要約は常に生成し、REVIEW_FINAL.md の冒頭に記載する。

---

## Phase 2: 外部ツールスキャン

ユーザーが外部ツール使用を「する」と回答した場合のみ実行する。

スクリプトを実行し、結果を変数に保持する。

```bash
bash scripts/pr-review-external.sh "$WORKTREE_DIR" "$BASE_BRANCH"
# → stdout に === CODEX_RESULT === と === CR_RESULT === のセクションで結果が出力される
```

結果はPhase 3でsubagentへの参考情報として渡し、
Phase 4でREVIEW_FINAL.mdの末尾「外部ツール結果」セクションに要約を記載する。

---

## Phase 3: レビュー実行

### Quick モード（並列数 1）

subagentは使わない。あなた（main agent）自身がworktree上でレビューを行う。
`references/review_criteria.md` のセクションA〜Eすべてを参照し、
`templates/review_final.md.tmpl` のフォーマットに従って `${REVIEW_DIR}/REVIEW_FINAL.md` を直接書く。

Phase 2で外部ツール（Codex/CodeRabbit）を実行していた場合は、
その結果も参照してレビューに反映する。
Quickモードでも外部ツールは併用可能（AskQuestionで「する」を選択した場合）。

Quick モードでも、REVIEW_FINAL.md を書く前に各指摘に対してセルフチェックを行うこと:

- [ ] 「問題なし」と結論していないか → 結論が「問題なし」なら指摘ではなく「分析メモ」セクションに書く
- [ ] アクショナブルか → 具体的な修正アクションがないなら指摘にしない
- [ ] ユーザーの質問への回答を指摘に混ぜていないか → 回答は「分析メモ」セクションに書く
- [ ] 既存パターンとの比較を書く場合、既存コードの実行経路（同期/非同期、app-api/tasks-api）を実際に確認したか

セルフチェックに通らない項目は「指摘一覧」から除外し、必要なら「分析メモ」に移す。

### Standard / Deep モード（並列数 2以上）

subagentを使って並列レビューを行う。

#### 3-1. 観点の振り分け

`references/review_criteria.md` のセクション A〜E を、並列数に応じて各subagentに割り当てる。

振り分けルール:
- 並列数 2: agent1=[A, D], agent2=[B, C, E]
- 並列数 3: agent1=[A], agent2=[B, D], agent3=[C, E]
- 並列数 4: agent1=[A], agent2=[B], agent3=[C], agent4=[D, E]
- 並列数 5: agent1=[A], agent2=[B], agent3=[C], agent4=[D], agent5=[E]

ユーザーが「注力観点」を指定した場合:
- その観点に最も近いセクションを担当するagentに、注力指示を追加で渡す
- 注力観点が既存セクションに当てはまらない場合は、最も関連性の高いagentの指示に追記する

必ず全セクション(A〜E)がいずれかのagentに割り当てられていることを確認すること。
割り当て漏れがあると、その観点のレビューが完全に欠落する。

#### 3-2. subagent起動

各subagentを **並列に** 起動する。各subagentは `claude --print` で実行し、結果をstdoutで受け取る。

各subagentに渡す情報:
1. 担当セクションの内容（review_criteria.md から該当部分を抽出）
2. 担当外セクションの一覧（「これらは他のagentが担当するため言及不要」と明示）
3. PRのコンテキスト情報（タイトル、説明、ベースブランチ、ユーザー提供の追加コンテキスト）
4. 外部ツールの結果（Phase 2の結果がある場合。重複指摘を避けるための参考情報）
5. 出力フォーマットの指示（下記参照）

subagent起動コマンドの例:

```bash
claude --print \
  -p "あなたはPRレビューの担当者です。

## あなたの担当観点
${ASSIGNED_SECTIONS}

## 担当外（言及不要）
${OTHER_SECTIONS}

## PRコンテキスト
${PR_CONTEXT}

## 外部ツール結果（参考・重複指摘は避けること）
${EXTERNAL_RESULTS}

## 指示
1. worktree上のコードを実際に読み、PRの変更内容を調査せよ
2. 担当観点に基づいて問題点を洗い出せ
3. 指摘にファイルパスと行番号を書く際、該当行を含む前後5行のコードブロックを必ず引用せよ。引用なしの指摘は出力してはならない
4. 以下のフォーマットで各指摘を出力せよ。調査した内容に基づき、根拠を手厚く書くこと

### [severity番号]. [指摘タイトル] [[severity] / [観点カテゴリ]]
\`ファイルパス:L行番号(-L終了行)\`

指摘の概要（1-2文）

**なぜ問題か:**
この指摘が問題である理由を具体的に説明。

**該当コード周辺の状況:**
該当箇所の前後でどんな処理が行われているか。
関連する既存コードのパターンや前例があればそれも記載。

---

severityは以下の3段階:
- Critical: セキュリティリスク、データ損失、本番障害に直結する問題
- Suggestion: 設計改善、保守性向上、既存パターンとの整合
- Nit: 軽微な改善提案、スタイル、命名

指摘がなければ「担当観点において問題は検出されませんでした」と出力。
" \
  --cwd "$WORKTREE_DIR"
```

重要: 各subagentは必ずworktree上のコードを実際に読んで調査すること。
diffだけでなく、周辺コードや既存の類似実装も確認した上で指摘を書くこと。

Phase 4 の検証ステップで、引用コードと指摘内容の整合性を確認する。

#### 3-3. 結果の収集

各subagentの出力（stdout）を収集する。
これらはPhase 4で統合される。

---

## Phase 4: 統合・出力（Standard/Deep のみ）

全subagentのstdout出力を統合して `${REVIEW_DIR}/REVIEW_FINAL.md` を生成する。

### 4-1. 指摘の検証（Verification）

subagentの指摘を統合する **前に**、各指摘の妥当性を検証する。

#### Standard モード: main agent によるスポットチェック

main agent が各指摘の該当ファイル・行番号を Read で読み、以下を確認する:

- 引用コードが実際にその行に存在するか
- 引用コードと指摘内容が一致しているか
- 指摘の前提となる事実が正しいか

事実誤認が見つかった指摘は **除外** する。

#### Deep モード: 検証 agent による独立チェック

指摘数が多い場合は、専用の検証agentを起動する。

検証agentに渡す情報:
1. 全subagentの指摘リスト（ファイルパス、行番号、指摘内容）
2. worktreeのパス

検証agentは各指摘に対して `valid` / `invalid` / `needs-revision` を判定する。
main agentは `invalid` を除外し、`needs-revision` は検証コメントを踏まえて修正する。

### 4-2. 統合

検証を通過した指摘のみを対象に、以下のルールで統合する:

1. **各agentの記述を尊重**: 指摘の「なぜ問題か」「該当コード周辺の状況」はsubagentの出力をそのまま使う。main agentの役割はソート・番号付与・重複排除のみ。
2. **severity順にソート**: Critical → Suggestion → Nit の順に並べる。同一severity内ではセキュリティ関連を上位にする。
3. **番号の付与**: severity接頭辞付きの通し番号を振る（C-1, C-2, S-1, S-2, N-1...）
4. **重複排除**: 複数agentが同一箇所・同一内容の指摘を出した場合、より詳しい方を採用し、もう一方は除外する。
5. **外部ツール結果の記載**: Phase 2で外部ツールを使用した場合、末尾の「外部ツール結果」セクションにCodex/CodeRabbitの指摘要約と、上記指摘との重複関係を記載する。

出力ファイルのフォーマットは `templates/review_final.md.tmpl` に従う。

コンテキスト要約は常にREVIEW_FINAL.mdの冒頭に記載する（Phase 1-2 参照）。

---

## Phase 5: 完了報告

`${REVIEW_DIR}/REVIEW_FINAL.md` の場所をユーザーに伝える。

worktreeは削除しない。再レビューや追加調査でユーザーが使う可能性があるため、
クリーンアップはユーザーに委ねる。不要になったらユーザーが以下で削除できる:

```bash
git worktree remove "../${REPO_NAME}-pr-${PR_NUMBER}"
```

---

## Runtime生成物

```
reviews/
└── {branch-name}/             ← ブランチ名（/ は - に置換）
    └── REVIEW_FINAL.md        ← 最終レビュー結果（唯一の成果物）
```

`reviews/` は `.git` > exclude対象にしていることを前提とする
