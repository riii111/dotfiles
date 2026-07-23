---
name: completion-report
description: |
  merge済みの担当PRについて、後続taskへの引継ぎやリスクをCompletion Noteとして共有状態へ保存する。task-workerからmerge後の報告を保存するとき、または親から未保存Noteの作成を依頼された子セッションで使う。
---

# Completion Report

担当PRがmerge済みの場合だけ使う。PRの通常要約は繰り返さず、作業で初めて分かった情報だけを記録する。

1. 先に保存済みか確認する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py completion-note-status <orchestration-id> \
  --task-id <task-id>
```

`saved`が`true`なら成功として終える。Noteを再生成せず、内容も返さない。
2. `saved`が`false`なら、`gh pr view`で対象PRの`mergedAt`とmerge commitを確認する。未merge、PR対応が不明、または状態が矛盾するときは保存しない。
3. 次の任意項目だけを持つJSON objectを作る。共有事項がなければ空のobjectにする。
   - `risks`: 未解決の懸念やリリース後に確認する点
   - `handoff`: 後続taskへ伝える変更・制約・避けるべき経路
   - `review_learnings`: 他taskにも使えるレビュー上の学び
   - `technical_debt`: 今回の対象外にした改善候補
4. 状態管理ツールで保存する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py record-completion-note <orchestration-id> \
  --task-id <task-id> \
  --note-file <completion-note-json-path>
```

保存の成功だけを親へ伝える。`risks`と`handoff`は依存taskを開始するときに状態管理ツールが渡す。保存失敗や既存Noteとの不一致は解決せずに後続taskの開始を依頼しない。
