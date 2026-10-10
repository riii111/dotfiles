---
name: task-orchestration
description: |
  ユーザーの指示とタスク管理元を読み、開始可能なtaskを`$task-session-launch`へ渡す。
  最初のタスク開始や、後から状況を確認して再開するときに使う。
---

# Task Orchestration

統括役はCodexを既定とし、ユーザーがClaudeでの統括を指示した場合（AppでClaudeを選択した場合を含む）にClaudeを使う。workerは既定Claude、reviewerはCodexとし、統括役の選択から変更しない。

開始時と再開時に、ユーザーが指定したタスク管理元を読む。
タスク管理元に記載された依存関係を確認する。
依存が満たされていて、互いに並行して進められるtaskをすべて開始対象にする。
管理元にない合意や必要な依存成果・担当境界は参照文書へ記録する。開始対象を選んだ同じturnで、タスクID・参照文書のパスとURL・許可された到達点を`$task-session-launch`へ渡す。
中間報告で停止しない。

開始済みか完了済みかはタスク管理元、既存のCodex Task、GitHubのPRを見て判断する。
harnexus内のClaudeは`mcp__codex_link__wait_threads`・`read_thread`・`send_message_to_thread`を使い、自分が起動したworkerを追う。
進捗はwait_threadsの最新snapshotとcursorで追い、履歴が必要な場合だけread_threadで最新1turn・出力なしから読む。不足する履歴や出力だけ追加取得する。
追加指示は最新の最終回答・明示エラー・履歴の進行に基づき、不足に限定する。idleやtimeoutだけで停止と判断せず、worker/reviewerの結果受取方式を変更しない。harnexus-taskの結果不明・モデル不一致は再送せず、ユーザーへ確認を求める。
merge通知の自動受信や親Taskの自動再開は扱わない。
