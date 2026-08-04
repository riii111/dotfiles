---
name: task-orchestration
description: |
  ユーザーの指示とタスク管理元を読み、開始可能なtaskをtask-session-launchへ渡す。最初のタスク開始や、後から状況を確認して再開するときに使う。
---

# Task Orchestration

開始時と再開時に、ユーザーの指示、タスク管理元の最新task、直接依存、現在状態を読む。依存が完了していて今すぐ着手できるtaskを選び、task名、本文、依存成果物、repository、baseを`task-session-launch`へ渡す。

開始済みか完了済みかはタスク管理元、既存のCodex Task、GitHubのPRを見て判断する。次に呼ばれたときも同じ情報源を読み直す。merge通知の自動受信や親Taskの自動再開は扱わない。
