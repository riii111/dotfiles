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
   - `prompt`は下記の引き継ぎ情報とtask-workerリンクで組み立てる。
3. `codex_app__create_thread`を一度呼ぶ。

## 起動prompt

workerの実行主体（Claude / Codex）、開始対象、タスク管理元、許可された到達点を伝える。
管理元から読める本文や、適用されるAGENTS.mdの規約、モデル設定、task-workerの手順・完了条件は転載しない。
次の情報は必要な場合だけ加える。

- 管理元にないユーザーとの合意、対象外、追加の許可・制約。
- 未mergeの依存成果のbranch・SHA・PR base、並行作業との担当境界。
- worktreeへ入らない資料や規約の絶対パス、親orchestration Task ID。
- 調査の入口となるファイルパスと、判断に影響する未確認事項。コードから再取得できる説明は省く。

同じインストール先の`task-worker/SKILL.md`の実在を確認し、絶対パスのリンクを渡す。
Claude workerではharnexusが本文を添付するため、裸のSKILL名ではなく下記の形式を使う。
task-review-cycleはtask-workerからレビュー段階で読む。

```text
[$task-worker](/Users/a81803/.codex/skills/task-worker/SKILL.md)
```

## 制約

`clientThreadId`は`worktree`準備中の正常な結果として扱う。
`clientThreadId`が返っても`codex_app__create_thread`を重ねて呼ばない。
