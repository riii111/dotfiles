---
name: task-worker
description: |
  割り当てられたtaskを再読し、Git worktreeで実装、独立レビュー、必須検証、Draft PRとCI成功まで進める。
  `$task-session-launch`から起動された実装Taskで使う。
---

# Task Worker

参照文書の先頭をタスク管理元とし、対象タスク・合意・依存成果・関連規約を確認する。再開時は必要な文書を読み直す。起動依頼の「進めてよい範囲」を到達点とする。
割り当てられたGit worktreeでConventionalな英語branchを作り、実装する。
自身のTask IDはCodex・Claudeとも`CODEX_THREAD_ID`とする。
候補をcommitする。実装・検証までの場合は検証結果とcommitを報告して完了する。Draft PR以降の場合は[task-review-cycle](../task-review-cycle/SKILL.md)を読み、独立レビューを受ける。
参照資料の相対パスは、そのSKILL.mdのディレクトリを基準に解決する。
親への通知や完了記録は扱わない。

## 判断ログ

タスク・ADR・規約で決まっていない点を自分で選び、それが仕様・互換性・運用・変更コスト・公開インターフェース・担当範囲に影響するなら、worktreeの`.reviewctl/decisions.md`へその場で追記する。命名や内部の関数分割のような細かな選択は記録しない。`.reviewctl/`が無ければ`*`だけの`.gitignore`を置いて作る。1件の書式は次のとおり。

```markdown
## <決めた点>
- 選択: <選んだもの>
- 他の候補: <検討した他の案>
- 理由: <選んだ理由>
```

ログがあれば、レビュー依頼JSONのdocumentRefsの末尾にその絶対パスを加える。

## 修正と完了

編集中と修正時は影響箇所を検証する。Blockingと採用する任意改善をまとめて修正・commitし、同じreview TaskでLGTMまで続ける。Non-blockingの未対応だけでは再レビューしない。
最終検証やCIで候補を修正した場合も、新headを独立レビューする。全検証は修正のたびに繰り返さず、LGTM後の最終headでリポジトリ所定の必須検証を完了する。

そのheadを通常のpushで公開し、create-pr SKILL、なければPR templateと直近の慣例に従ってDraft PRを作成・更新する。
PRタイトルは、タイトルだけで変更が分かるように「誰が何をすると何が変わるか」を具体的に書く（例：「決済APIが5xxを返したら指数バックオフで再送する」）。「安定性を高める」のような効能だけの表現にしない。本文の冒頭も同じ書き方で、変更前後の挙動の違いを1〜3文で書く。接頭辞などの形式はcreate-pr SKILLや慣例に従い、文章は[japanese-tech-writing](../japanese-tech-writing/SKILL.md)に従う。ディスパッチの朝刊はタイトルを言い換えずに載せる。
reviewerが`.reviewctl/packet.yaml`に書く[レビュー資料](../task-review-cycle/references/packet.md)は人に見せない材料なので、完了報告・PR本文・PRのコメントに内容を書かない。Draft PRを作った後、PRのheadと資料の`head`が一致することを確かめ、そのheadのcheck結果をGitHubから取り直して`ci`（「未取得」の理由も含む）・`ci_url`と、`unconfirmed`のうちCI jobの分をファイル上で書き換える。一致しなければ`ci`を「未取得: PRのheadが資料と不一致」、`ci_url`を空にする。新しいheadをpushしても、そのheadでLGTMを受けるまで資料の`head`は書き換えない。
完了条件はPR headとreview済みheadの一致、そのheadの必須検証・独立LGTM・CI成功とする。
完了報告のGit・PR・CI状態は直近の確認結果に基づき、未追跡・失敗などを未確認のまま断言しない。
Ready化・mergeは別途依頼された場合だけ行い、その直前に現在のbaseとのmerge可否と意味的な競合を確認する。

## Review基点

最初のレビュー直前にbase branchをfetchし、そのtipを必要に応じて取り込む。branch名とPR URLを依頼JSONに記録し、harnexus-taskが取得したbase/head SHAをreview基点と候補にする。

baseの進行だけでは取り込み・全検証・再レビューを繰り返さない。実際の競合や変更行・挙動の重複で上流を取り込んだ場合だけ、そのbase SHAへ基点を更新して必要な検証と再レビューを行う。
