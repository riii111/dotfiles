---
name: task-worker
description: |
  オーケストレーションで割り当てられたタスクを再読し、専用worktreeで実装、全検証、Draft PR作成まで進める。PR作成後または再開時は共通の状態遷移スクリプトが返す次の工程へ引き継ぐ。
---

# Task Worker

担当するのはタスク再読からDraft PR作成までである。レビューは`task-review-cycle`、merge後の記録は`completion-report`へ任せる。

## 入力

- オーケストレーションID
- task IDとタスク管理元
- repositoryとbase
- 完了方針。`manual`または`auto`。既定は`manual`

開始時と再開時は、タスク管理元の最新本文、直接依存、添付資料、repository規約を読む。次に`task-orchestration`の`orchestration_state.py context`を実行し、taskの子セッションID、許可repository、PR対応を確認する。会話上の進捗で代用しない。

状態遷移スクリプトの`init`を一度実行する。スクリプトはオーケストレーションID、task ID、`context`で確認した子セッションIDから一意な絶対パスを決める。main checkoutと専用worktreeのcwdへ依存せず、reset後に同じtask IDが再作成されても古いworker状態を読まない。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py init <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --policy <manual-or-auto>
python3 <task-worker-skill-directory>/scripts/worker_transition.py next <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id>
```

状態JSONのschemaと更新はスクリプトが扱う。外部操作後は結果をevent JSONにし、`apply-event`へ渡す。返された`action`が`implement`なら次の工程を行い、それ以外は絶対状態パスとactionを`task-review-cycle`へ渡す。矛盾や未知の状態でエラーになった場合は自動復旧しない。

## 実装

1. 指定baseの最新状態と既存worktreeを確認する。なければ、task IDを含まないconventionalな英語branch名で通常の`git worktree add`を使う。
2. 近傍実装だけでなく、呼び出し元、公開境界、永続化形式、設定、テスト、失敗経路まで調べる。
3. 小さく意味的にまとまったConventional Commitsで実装する。
4. repository所定のformat、lint、静的検査、test、buildをすべて通す。
5. PR templateと直近の慣例に従ってDraft PRを作る。PR本文にtask IDや管理用markerを書かない。
6. 作成直後に`orchestration_state.py record-pr`を一回実行する。失敗したらPRを作り直さず、作成済みPRとエラーを報告して停止する。
7. `pr_created` eventへhead SHAを入れて適用し、`task-review-cycle`へ引き継ぐ。

worktreeやtaskとの対応が不明、baseが違う、PRがclosed、検証失敗が残る場合は停止する。
