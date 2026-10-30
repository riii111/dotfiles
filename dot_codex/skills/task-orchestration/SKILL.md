---
name: task-orchestration
description: |
  ユーザーの指示とタスク管理元を読み、開始可能なtaskを`$task-session-launch`へ渡す。
  最初のタスク開始や、後から状況を確認して再開するときに使う。
---

# Task Orchestration

`harnexus-task environment`が`"host":"claude"`を返す場合は、先に末尾の「Claude CodeのCloud」を読む。

統括役はCodexを既定とし、ユーザーがClaudeでの統括を指示した場合（AppでClaudeを選択した場合を含む）にClaudeを使う。
workerは既定Claude、reviewerはCodexとし、統括役の選択から変更しない。

開始時と再開時に、ユーザーが指定したタスク管理元を読む。
タスク管理元に記載された依存関係を確認する。
依存が満たされていて、互いに並行して進められるtaskをすべて開始対象にする。
依存先が未完了でも、依存先のPRに積めるtaskは開始対象にする。
開始対象ごとに、[PRの積み方](../task-session-launch/references/stacking.md)の基準で積むかどうかを決める。
積み先のPRがまだないtaskは、そのPRができるまで開始しない。
管理元にない合意や必要な依存成果・担当境界は参照文書へ記録する。
開始対象を選んだ同じturnで、タスクID・参照文書のパスとURL・許可された到達点を`$task-session-launch`へ渡す。
中間報告で停止しない。

開始済みか完了済みかはタスク管理元、既存のCodex Task、GitHubのPRを見て判断する。
harnexus内のClaudeは、自分が起動したworkerを追う。
追うには`mcp__codex_link__wait_threads`・`read_thread`・`send_message_to_thread`を使う。
進捗はwait_threadsの最新snapshotとcursorで追い、履歴が必要な場合だけread_threadで最新1turn・出力なしから読む。
不足する履歴や出力だけ追加取得する。
追加指示は最新の最終回答・明示エラー・履歴の進行に基づき、不足に限定する。
idleやtimeoutだけで停止と判断せず、worker/reviewerの結果受取方式を変更しない。
harnexus-taskの結果不明・モデル不一致は再送せず、ユーザーへ確認を求める。
merge通知の自動受信や親Taskの自動再開は扱わない。

## Claude CodeのCloud

`harnexus-task environment`が`"host":"claude"`を返す場合、このセッションのClaudeが統括役になる。
workerはtask-session-launchの「Claude CodeのCloud」で起動する。
開始済みかどうかは、既存のCodex Taskの代わりに`list_sessions`で確かめる。
workerの完了・停止・指摘対応の報告は、各workerからの`send_message`で受け取る。
この報告で統括役のturnが始まるため、「親Taskの自動再開は扱わない」は当てはまらない。
進捗は`get_session`の`status_bucket`と`list_events`で確かめる。
`status`は失敗したturnでも`idle`と読めるため、判断に使わない。
mcp__codex_link__のツールと、harnexus-taskのlaunch・state・resolveは使わない。
