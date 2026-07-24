---
name: task-completion-recovery
description: |
  task-orchestrationの親FSMが返したCompletion Note回収操作を既存の子セッションで実行する。recover_completion_noteまたはwait_completion_noteを引き継いだときに使う。
---

# Task Completion Recovery

Completion Note回収の外部操作だけを担当する。回収対象や次操作を独自に選ばず、`orchestration_transition.py`のactionとdetailsを正本にする。

## 回収する

`orchestration_state.py completion-note`で対象taskを先に再読する。保存済みなら、出力のschemaどおり`completion_note_observed` eventを適用する。

未保存の`recover_completion_note`では、同じaction tokenを持つ回収turnが対象Threadにないことを確認してから、`context`に保存された子セッションだけを再開する。action tokenを添え、`completion-report`による保存を依頼する。返されたturn IDとwait cursorをeventへ入れる。新しい子セッションは作らない。

`wait_completion_note`では、保存済みturn IDとcursorで同じturnを待つ。待機後はCompletion Noteを再読し、観測した結果を出力のevent schemaどおりに適用する。timeout時に依頼を重ねない。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_transition.py apply-event <orchestration-id> \
  --source-revision <task-source-revision> \
  --event-file <event-json-path>
```

返された`executor_skill`が自分なら続け、それ以外は`task-orchestration`へ戻す。eventの許可条件と次actionは状態遷移ツールへ任せ、状態JSONは手編集しない。
