---
name: task-worker
description: |
  オーケストレーションで割り当てられたタスクを再読し、専用worktreeで実装、全検証、Draft PR作成まで進める。task-orchestrationから起動された実装タスクの開始・再開と、PR作成後にtask-review-cycleへ引き継ぐときに使う。
---

# Task Worker

担当するのはタスク再読からDraft PR作成までである。レビューは`task-review-cycle`、merge後の記録は`completion-report`へ任せる。

## 入力

- オーケストレーションID
- task IDとタスク管理元
- repositoryとbase
- 完了方針。`manual`または`auto`。既定は`manual`

不足値は親セッションのGoalと会話履歴から補う。repository、base、オーケストレーションID、task IDを確定できなければ推測せずユーザーへ返す。

開始時と再開時は、タスク管理元の最新本文、直接依存、添付資料、repository規約を読む。次に`task-orchestration`の`orchestration_state.py context`を実行し、taskの子セッションID、許可repository、PR対応を確認する。会話上の進捗で代用しない。担当repositoryが`pull_request_repositories`に含まれなければ、実装やPR作成へ進まず親へ設定不足を返す。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

状態遷移スクリプトの`init`を実行する。既存状態があればpolicyを上書きせず現状態を返すため、開始時と再開時のどちらでも同じコマンドを使う。完了方針の変更は後続の`policy_changed` eventで反映する。スクリプトはオーケストレーションID、task ID、`context`で確認した子セッションIDから一意な絶対パスを決める。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py init <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --policy <manual-or-auto>
python3 <task-worker-skill-directory>/scripts/worker_transition.py next <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id>
```

状態JSONのschemaと更新はスクリプトが扱う。外部操作後は結果をevent JSONにし、次を実行する。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py apply-event <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --event-file <event-json-path>
```

返された`action`が`implement`なら次の工程を行う。それ以外は同じセッションで直ちに`$task-review-cycle`を適用し、オーケストレーションID、task ID、child thread ID、repository、base、完了方針、状態の絶対パス、actionをすべて引き継ぐ。skillを自動適用できなければ、その`SKILL.md`を全文読んで続行する。矛盾や未知の状態でエラーになった場合は自動復旧しない。

`context`に追跡PRがあるのにworker状態が`absent`なら、PRを作り直さず、GitHubで確認した既存PRのhead SHAを`pr_created` eventとして適用する。

## 実装

1. 指定baseの最新状態と既存worktreeを確認する。なければ、task IDを含まないconventionalな英語branch名で通常の`git worktree add`を使う。
2. 近傍実装だけでなく、呼び出し元、公開境界、永続化形式、設定、テスト、失敗経路まで調べる。
3. 小さく意味的にまとまったConventional Commitsで実装する。
4. repository所定のformat、lint、静的検査、test、buildをすべて通す。
5. PR templateと直近の慣例に従ってDraft PRを作る。PR本文にtask IDや管理用markerを書かない。
6. 作成直後に次を一回実行する。失敗したらPRを作り直さず、作成済みPRとエラーを報告して停止する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py record-pr <orchestration-id> \
  --task-id <task-id> --repository <owner/repository> --number <pr-number>
```

7. `pr_created` eventへhead SHAを入れて適用し、`task-review-cycle`へ引き継ぐ。

worktreeやtaskとの対応が不明、意図しないbase、PRがclosed、検証失敗が残る場合は停止する。
