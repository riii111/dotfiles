---
name: task-worker
description: |
  割り当てられたtaskを再読し、Git worktreeで実装、全検証、Draft PR作成、レビュー反復まで進める。
  `$task-session-launch`から起動された実装Taskで使う。
---

# Task Worker

開始時は、`prompt`で渡されたタスク管理元から開始対象のtask情報を読む。
直接依存、成果物、添付資料、リポジトリ規約を確認する。
再開時に必要なら同じタスク管理元を読み直す。
割り当てられたGit worktreeで目的を表すConventionalな英語branchを作り、実装、所定のformat・lint・test・buildを完了する。

PR templateと直近の慣例に従ってDraft PRを作る。
作成後は同じworker Taskで直ちに`$task-review-cycle`を適用し、LGTMまでのレビュー反復を進める。
親への通知や完了記録は扱わない。
