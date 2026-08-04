---
name: task-session-launch
description: |
  開始対象taskのCodex TaskをGit worktreeで作成し、タイトルと具体的なGoalを設定する。
  task-orchestrationから開始対象を受け取ったときに使う。
---

# Task Session Launch

開始対象taskのrepositoryに対応するCodex projectを選ぶ。
指定baseからGit worktreeのCodex Taskを一度作成する。
タイトルは`[<task-id>] <task title>`にする。

Goalにはtaskの最新本文、直接依存と成果物、repository、base、完了条件を入れる。
`$task-worker`を使い、repo規約を読んで割り当てられたGit worktreeで実装し、全検証後にDraft PRを作るよう依頼する。
作成後の進行はworker Taskに任せる。
