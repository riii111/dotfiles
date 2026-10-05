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
   - `startingState`は開始branchを明示された場合だけ`{type: "branch", branchName: <branch>}`を指定する。
   - `title`は`Impl <taskの短い識別子>`とし、task titleやPR titleは含めない。
   - `model: claude-opus-5-5`、`thinking: medium`を既定とし、ユーザーの明示指定を優先する。
   - `prompt`は[起動依頼](references/worker.md)を使い、下記の引き継ぎ情報を埋める。
3. `codex_app__create_thread`を一度呼ぶ。

## 起動prompt

管理元から読める本文や、適用されるAGENTS.mdの規約、モデル設定、task-workerの手順・完了条件は転載しない。
additional_contextは次のうち必要な情報だけを含め、空なら欄ごと省く。

- 管理元にないユーザーとの合意、対象外、追加の許可・制約。
- 未mergeの依存成果のbranch・SHA・PR base、並行作業との担当境界。
- worktreeへ入らない資料や規約の絶対パス、親orchestration Task ID。
- 調査の入口となるファイルパスと、判断に影響する未確認事項。コードから再取得できる説明は省く。

worker_skill_pathは同じインストール先の実在する`task-worker/SKILL.md`の絶対パスとする。
Claudeへの本文添付に必要なSKILLリンク形式を維持し、レビュー手順はtask-workerから必要な段階で読む。

## 制約

`clientThreadId`はworktree準備中の受理結果であり、重複作成しない。
