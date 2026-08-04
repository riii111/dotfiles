---
name: task-worker
description: |
  割り当てられたtaskを再読し、専用worktreeで実装、全検証、Draft PR作成、レビュー反復まで進める。task-session-launchから起動された実装Taskで使う。
---

# Task Worker

開始時と再開時に、タスク管理元の最新本文、直接依存と成果物、添付資料、repository規約を読む。指定baseから専用worktreeと目的を表すConventionalな英語branchを作り、実装、所定のformat・lint・test・buildを完了する。

PR templateと直近の慣例に従ってDraft PRを作る。作成後は同じworker Taskで直ちに`$task-review-cycle`を適用し、LGTMまでのレビュー反復を進める。親への通知や完了記録は扱わない。
