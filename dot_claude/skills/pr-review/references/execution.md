# PR Review — Execution (Phase 2-4)

Phase 1 でユーザーから受け取った回答に基づいて実行する。

---

## Phase 2: レビュー実行

### 外部ツール（ユーザーが「する」と回答した場合のみ）

スクリプトを **Bash `run_in_background: true`** で起動してからレビュー本体に入る。
結果は Phase 3 の統合時に参照する。

```bash
bash ~/.claude/skills/pr-review/scripts/pr-review-external.sh "$WORKTREE_DIR" "$BASE_BRANCH"
# → stdout に === CODEX_RESULT === と === CR_RESULT === のセクションで結果が出力される
```

### Quick モード

subagentは使わない。main agent 自身が `$WORKTREE_DIR` 上でレビューを行う。
`references/review_criteria.md` のセクションA〜Eすべてを参照し、
`templates/review_final.md.tmpl` のフォーマットに従って `${REVIEW_DIR}/REVIEW_FINAL.md` を直接書く。

REVIEW_FINAL.md を書く前に各指摘に対してセルフチェックを行うこと:

- [ ] 「問題なし」と結論していないか → 「分析メモ」セクションに書く
- [ ] アクショナブルか → 具体的な修正アクションがないなら指摘にしない
- [ ] ユーザーの質問への回答を指摘に混ぜていないか → 「分析メモ」に書く
- [ ] 既存パターンとの比較を書く場合、既存コードの実行経路を実際に確認したか

セルフチェックに通らない項目は「指摘一覧」から除外し、必要なら「分析メモ」に移す。

Quick モードは Phase 2 完了後、Phase 4（完了報告）へ進む。Phase 3 はスキップ。

### Standard / Deep モード

subagentを使って並列レビューを行う。

#### 観点の振り分け

`references/review_criteria.md` のセクション A〜E をラウンドロビンで振り分ける（例: 2並列→agent1=[A,C,E], agent2=[B,D]）。
全セクション割り当て必須（漏れ＝その観点が欠落する）。
ユーザーの「注力観点」は、最も近いセクション担当agentに追加指示として渡す。

#### subagent起動

各subagentを **並列に** 起動する。**Agent ツール** (`run_in_background: true`) を使い、各agentのプロンプト内でworktreeの絶対パスを明示すること。

> **注意**: `claude --print --cwd` は存在しない。Bash経由の `claude --print` もstderrが消失しやすく失敗時のデバッグが困難なため、Agent ツールを使うこと。

各subagentに渡す情報:
1. 担当セクションの内容（review_criteria.md から該当部分を抽出）
2. 担当外セクションの一覧（「これらは他のagentが担当するため言及不要」と明示）
3. PRのコンテキスト情報（タイトル、説明、ベースブランチ、ユーザー提供の追加コンテキスト）
4. 出力フォーマットの指示: `templates/review_final.md.tmpl` の指摘フォーマットに従う
5. **worktreeの絶対パス**（「すべてのファイル読み取りはこのパスを使え」と明示）

subagentへの指示要点:
- worktree上のコードを実際に読み、diffだけでなく周辺コードや既存の類似実装も確認すること
- 指摘には該当行の前後5行のコードブロック引用を必須とする。引用なしの指摘は不可
- severity: Critical（本番障害直結）/ Suggestion（設計改善）/ Nit（軽微）
- 指摘なしの場合は「担当観点において問題は検出されませんでした」と出力

---

## Phase 3: 検証・統合・出力（Standard/Deep のみ）

全subagentの出力を統合して `${REVIEW_DIR}/REVIEW_FINAL.md` を生成する。

### 3-1. 指摘の検証

subagentの指摘を統合する **前に**、各指摘の妥当性を検証する。

#### Standard モード: main agent によるスポットチェック

main agent が各指摘の該当ファイル・行番号を Read で読み、以下を確認する:

- 引用コードが実際にその行に存在するか
- 引用コードと指摘内容が一致しているか
- 指摘の前提となる事実が正しいか

事実誤認が見つかった指摘は **除外** する。

#### Deep モード: 検証 agent による独立チェック

専用の検証agentを起動する。

検証agentに渡す情報:
1. 全subagentの指摘リスト（ファイルパス、行番号、指摘内容）
2. worktreeのパス

検証agentは各指摘に対して `valid` / `invalid` / `needs-revision` を判定する。
main agentは `invalid` を除外し、`needs-revision` は検証コメントを踏まえて修正する。

### 3-2. 統合

検証を通過した指摘のみを対象に、以下のルールで統合する:

1. **各agentの記述を尊重**: 指摘の「なぜ問題か」「該当コード周辺の状況」はsubagentの出力をそのまま使う。main agentの役割はソート・番号付与・重複排除のみ。
2. **severity順にソート**: Critical → Suggestion → Nit の順。同一severity内ではセキュリティ関連を上位。
3. **番号の付与**: severity接頭辞付きの通し番号（C-1, C-2, S-1, S-2, N-1...）
4. **重複排除**: 複数agentが同一箇所・同一内容の指摘を出した場合、より詳しい方を採用。
5. **外部ツール結果の記載**: Phase 2で外部ツールを使用した場合、末尾の「外部ツール結果」セクションに要約と重複関係を記載。

出力フォーマットは `templates/review_final.md.tmpl` に従う。
コンテキスト要約は常にREVIEW_FINAL.mdの冒頭に記載する。

---

## Phase 4: 完了報告

`${REVIEW_DIR}/REVIEW_FINAL.md` の場所をユーザーに伝える。

worktreeは削除しない。不要になったらユーザーが以下で削除できる:

```bash
git worktree remove "../${REPO_NAME}-pr-${PR_NUMBER}"
```

### Runtime生成物

```
reviews/
└── {branch-name}/             ← ブランチ名（/ は - に置換）
    └── REVIEW_FINAL.md        ← 最終レビュー結果（唯一の成果物）
```

`reviews/` は `.git` > exclude対象にしていることを前提とする。
