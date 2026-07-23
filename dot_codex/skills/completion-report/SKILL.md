---
name: completion-report
description: |
  merge済みの担当PRについて、作業で得た知見をCompletion Noteとして共有状態へ一度だけ保存する。task-review-cycleからmerge後に引き継ぐとき、または親から未保存Noteの回収を依頼されたときに使う。
---

# Completion Report

merge後のCompletion Note保存と親オーケストレーションへの完了通知を担当する。

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
2. 次を実行する。`complete`ならNote処理を繰り返さず手順7の通知へ進む。`record_completion_note`なら手順3へ進む。それ以外のactionでは停止する。

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

6. `completion_note_saved` event JSONを作り、次で適用する。返されたactionが`complete`であることを確認する。

```text
python3 <task-worker-skill-directory>/scripts/worker_transition.py apply-event <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> --event-file <event-json-path>
```

7. `context`の`parent_thread_id`を送信先にする。次で通知outboxを作成する。既存outboxと同じ通知ならその状態を返し、異なる内容では上書きしない。

```text
python3 <completion-report-skill-directory>/scripts/completion_notification.py \
  prepare <orchestration-id> --task-id <task-id> --worker-id <child-thread-id> \
  --repository <owner/repository> --number <pr-number> \
  --merge-commit <merge-commit>
```

`status`が`submitted`なら保存済み`submission_id`を確認して完了を報告し、再送しない。`pending`なら次のstdoutを変更せず`multi_agent_v1__send_input`のmessageへ渡し、targetへ親thread IDを指定する。

```text
python3 <completion-report-skill-directory>/scripts/completion_notification.py \
  payload <orchestration-id> --task-id <task-id> --worker-id <child-thread-id>
```

通知JSONはオーケストレーションID、task ID、PR、merge commit、`saved: true`だけを含む。Note本文や再planの指示を追加しない。空でない`submission_id`を取得したら次でoutboxへ保存し、`submitted`と同じIDを再読できた場合だけ通知済みとして完了を報告する。

```text
python3 <completion-report-skill-directory>/scripts/completion_notification.py \
  mark-submitted <orchestration-id> \
  --task-id <task-id> --worker-id <child-thread-id> \
  --submission-id <submission-id>
```

親が処理中でもsubmissionが受理されれば成功であり、同じturnへ割り込ませようとしない。保存、再読、既存Noteとの一致、`complete`確認、outbox、送信のいずれかに失敗した場合は完了扱いにしない。送信が失敗するか`submission_id`を確認できない場合はoutboxを`pending`のまま残し、通知未完了として判明した状態を報告する。再開時は最初から状態と証跡を再確認し、pendingの同じJSONを再送する。送信結果が不明な場合も同様に再送し、親側の冪等なplanへ重複排除を任せる。
