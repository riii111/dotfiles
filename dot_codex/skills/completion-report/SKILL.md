---
name: completion-report
description: |
  merge済みの担当PRについて、作業で得た知見をCompletion Noteとして共有状態へ一度だけ保存する。task-review-cycleからmerge後に引き継ぐとき、または親から未保存Noteの回収を依頼されたときに使う。
---

# Completion Report

merge後のCompletion Noteだけを担当する。

## 入力

- オーケストレーションID
- task ID
- child thread ID
- repositoryとPR番号

不足値は`orchestration_state.py context`から取得する。taskが未登録、予約中、子セッションIDが空、またはPR対応がなければ推測せず停止する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

1. `gh pr view`で担当PRの`state`、`mergedAt`、merge commitとtask対応を確認する。未mergeまたは矛盾時は保存しない。PRがmerge済みでworker状態がまだ未mergeなら、先に`merged` eventを適用する。
2. 次を実行し、`complete`ならeventを適用せず、保存済みと報告して終了する。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py next <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id>
```

3. 次でNoteを確認する。`saved: true`なら空Noteを含めて`completion_note_saved` eventを適用し、再生成しない。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py completion-note <orchestration-id> \
  --task-id <task-id>
```

4. 未保存なら、実装、レビュー、修正、最終検証から共有すべき内容だけを日本語のJSON objectにしてJSON fileへ保存する。使える項目は`risks`、`handoff`、`review_learnings`、`technical_debt`で、該当しない項目は省く。PR要約は入れず、共有事項がなければ空objectにする。
5. 次で保存し、同じ`completion-note`コマンドで再読する。`saved: true`かつ保存内容との一致を確認する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py record-completion-note <orchestration-id> \
  --task-id <task-id> --note-file <completion-note-json-path>
```

6. `completion_note_saved` event JSONを作り、次で適用する。`complete`を確認して保存完了だけを報告する。Note本文は親へ送らない。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py apply-event <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --event-file <event-json-path>
```

保存、再読、既存Noteとの一致確認の失敗は完了扱いにしない。
