---
name: completion-report
description: |
  merge済みの担当PRについて、作業で得た知見をCompletion Noteとして共有状態へ一度だけ保存する。
---

# Completion Report

merge後のCompletion Noteだけを担当する。

1. `gh pr view`で担当PRの`state`、`mergedAt`、merge commitとtask対応を確認する。未mergeまたは矛盾時は保存しない。
2. `orchestration_state.py completion-note`を実行する。`saved: true`なら空Noteを含めて完了済みとし、再生成しない。
3. 未保存なら、実装、レビュー、修正、最終検証から共有すべき内容だけを日本語のJSON objectにする。使える項目は`risks`、`handoff`、`review_learnings`、`technical_debt`で、該当しない項目は省く。PR要約は入れず、共有事項がなければ空objectにする。
4. `orchestration_state.py record-completion-note`で保存し、`completion-note`で再読する。`saved: true`かつ保存内容との一致を確認する。
5. 最新状態を`worker_transition.py`へ渡し、`complete`を確認して保存完了だけを報告する。Note本文は親へ送らない。

保存、再読、既存Noteとの一致確認の失敗は完了扱いにしない。
