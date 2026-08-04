---
name: task-session-launch
description: |
  選択済みtaskのCodex Taskを作成し、タイトルと具体的なGoalを設定する。task-orchestrationから開始対象を受け取ったときに使う。
---

# Task Session Launch

選択済みtaskのrepositoryに対応する保存済みprojectを決め、Codex Taskを一度作成する。タイトルは`[<task-id>] <task title>`にする。

Goalにはtaskの最新本文、直接依存と成果物、repository、base、完了条件を入れる。`$task-worker`を使い、repo規約を読んで専用worktree/branchで実装し、全検証後にDraft PRを作るよう依頼する。作成後の進行はworker Taskに任せる。
