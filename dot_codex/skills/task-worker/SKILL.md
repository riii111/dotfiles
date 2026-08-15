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

## Review基点

最終reviewを始める直前にbase branchを一度だけfetchし、その時点のtipを必要に応じて取り込む。
そのexact SHAをreview baseとして固定し、review Taskへはbranch名ではなく`<review base SHA>...<head SHA>`を渡す。

review開始後にbase branchが進んだことだけを理由に、取り込み・全検証・再reviewを繰り返さない。
Ready化・merge直前に現在のbaseとのmerge可否と意味的な競合を確認する。
実際の競合、または変更行・挙動の重複がある場合だけbaseを取り込み、必要な検証と再reviewを行う。
無関係なbase進行なら、固定したreview結果とheadのchecksを維持してmergeへ進む。
