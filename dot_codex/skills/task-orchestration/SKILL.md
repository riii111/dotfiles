---
name: task-orchestration
description: |
  ユーザーの指示とタスク管理元を読み、開始可能なtaskを`$task-session-launch`へ渡す。
  最初のタスク開始や、後から状況を確認して再開するときに使う。
---

# Task Orchestration

開始時と再開時に、ユーザーが指定したタスク管理元を読む。
タスク管理元に記載された依存関係を確認する。
依存が満たされていて、互いに並行して進められるtaskをすべて開始対象にする。
開始対象を選んだ同じturnで、タスク管理元と各開始対象をそれぞれ`$task-session-launch`へ渡す。
中間報告で停止しない。

開始済みか完了済みかはタスク管理元、既存のCodex Task、GitHubのPRを見て判断する。
次に呼ばれたときも同じ情報源を読み直す。
merge通知の自動受信や親Taskの自動再開は扱わない。
