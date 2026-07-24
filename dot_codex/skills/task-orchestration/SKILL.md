---
name: task-orchestration
description: |
  オーケストレーションIDに紐づくタスク群を毎回読み直し、永続FSMが返す一操作を実行工程へ引き継ぐ。最初のタスク開始、merge通知後の再開、開始済み・依存待ちタスクの整理に使う。
---

# Task Orchestration

task sourceの再読、完了通知の外部確認、親FSMの呼出し、実行工程への引継ぎだけを担当する。Completion Note回収は`task-completion-recovery`、子セッション作成は`task-session-launch`へ任せる。状態や操作順をSKILL側で再構築しない。

## 入力

- base。必須
- 最大並列数。既定は4
- Completion Reportまたはユーザーから受け取ったmerge情報。任意
- 子セッション用SKILL。既定は利用なし
- 完了方針。`manual`または`auto`。既定は`manual`
- 子セッションのmodelとthinking。任意

オーケストレーションIDは登録済み設定から自動解決する。baseだけは確定できなければユーザーへ判断を求める。`auto`は対象repositoryとtaskへ明示された場合だけ使う。

## 状態から一操作を得る

各turnの開始時に`context`を実行し、task sourceから全task、直接依存、状態履歴、優先順位を読み直す。ページングと依存先を省略しない。task sourceの版、更新時刻、または正規化した完全な内容のSHA-256を`source-revision`にする。

```text
python3 <skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

全taskを`{"tasks":[{"id":"TASK-1","dependencies":[],"order":0}]}`の形へ正規化する。`--completed`には、追跡PRのmerge証跡まで確認したtask、または開始前から完了していたことを初回読込と履歴で確認できるtaskだけを入れる。

```text
python3 <skill-directory>/scripts/orchestration_transition.py init <orchestration-id> \
  --tasks <normalized-tasks.json> \
  --completed <confirmed-task-id> \
  --max-parallelism <maximum-parallelism> \
  --policy <manual-or-auto> \
  --source-revision <task-source-revision>
```

同じ親turn内で出力を失った場合だけ`next`で再取得する。turnをまたぐ再開ではtask sourceを再読して`init`を使う。

## 完了通知

Completion Reportまたはユーザーからmerge情報を受け取ったら、`context`のtask・PR対応、GitHubのmerge状態とmerge commit、`completion-note`の`saved: true`を再読する。通知JSONを変更せず、確認したmerge commitとともに、現在のaction tokenとsource revisionを持つ`completion_notified` eventとして適用する。通知本文からtask情報や次操作を補わない。

```text
python3 <skill-directory>/scripts/orchestration_transition.py apply-event <orchestration-id> \
  --source-revision <task-source-revision> --event-file <event-json-path>
```

## 操作を引き継ぐ

出力の`executor_skill`があれば、同じセッションでそのSKILLを直ちに適用し、オーケストレーションID、task source、base、子セッション設定、source revision、FSM出力を渡す。skillを自動適用できなければ、その`SKILL.md`を全文読んで続行する。`executor_skill`がなければ`action`と`details`をそのまま結果として返す。

親SKILLは外部操作結果のevent名、field、再試行可否、次actionを判断しない。これらは状態遷移ツールの出力と検証へ任せる。
