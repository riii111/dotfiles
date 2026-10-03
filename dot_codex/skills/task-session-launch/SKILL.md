---
name: task-session-launch
description: |
  開始対象taskのCodex TaskをGit worktreeで作成し、タイトルと具体的な`prompt`を設定する。
  `$task-orchestration`から開始対象を受け取ったときに使う。
---

# Task Session Launch

## 手順

1. `codex_app__list_projects`を一度呼び、repositoryに対応する`projectId`を決める。
2. 次の内容で`codex_app__create_thread`の入力を組み立てる。
   - Git repositoryでは`target.environment.type`を`worktree`にする。
   - 通常はprojectのdefault branchからGit worktreeを作るため、`target.environment.startingState`を指定しない。
   - ユーザーが開始branchを明示した場合だけ、`target.environment.startingState`の`type`を`branch`にし、`branchName`をそのbranchにする。
   - `title`を`Impl <identifier>`にする。
   - `<identifier>`にはユーザーの入力とタスク管理元から対象を区別できる短い表記を選ぶ。
   - `title`にPR titleやtask titleを含めない。
   - `model`を`claude-opus-5-5`、`thinking`を`medium`にする。
   - ユーザーがmodelまたはreasoning effortを明示した場合だけ、対応する値をその指定で置き換える。
   - `prompt`にタスク管理元、開始対象、親orchestration Task ID（指定されている場合）を含める。
   - `prompt`にworkerの実行主体（Claude / Codex）を明記し、下記のSKILLリンクと読込指示を入れる。リポジトリ規約を読んで割り当てられたGit worktreeで実装するよう依頼する。
   - 作業と完了条件はリンクで渡すtask-workerに従わせる。検証・レビュー・PR作成の詳細を起動promptへ重複して書かない。
3. `codex_app__create_thread`を一度呼ぶ。

## SKILLの受け渡し

利用中のこのSKILLと同じインストール先にある`task-worker/SKILL.md`と`task-review-cycle/SKILL.md`の実在を確認し、絶対パスを使ったリンクを起動`prompt`へ入れる。
この環境のインストール先は`/Users/a81803/.codex/skills`。管理元の`dot_codex/skills`ではなく、適用済みファイルを渡す。

```text
[$task-worker](/Users/a81803/.codex/skills/task-worker/SKILL.md)
[$task-review-cycle](/Users/a81803/.codex/skills/task-review-cycle/SKILL.md)

task-workerを読んで実装し、レビュー工程ではtask-review-cycleを読んでください。
依存SKILLや参照資料は、そのSKILL.mdのディレクトリを基準にパスを解決して読んでください。
```

インストール先が異なる場合は、リンク先を確認した実際の絶対パスへ置き換える。
harnexusは`[$skill-name](/absolute/path/SKILL.md)`形式のリンク先本文をClaudeの入力へ添付する。裸の`$task-worker`などの文字列だけで本文が読み込まれるとは扱わない。
読めないSKILLがあれば、workerを起動する前に解消する。

## 制約

`clientThreadId`は`worktree`準備中の正常な結果として扱う。
`clientThreadId`が返っても`codex_app__create_thread`を重ねて呼ばない。
