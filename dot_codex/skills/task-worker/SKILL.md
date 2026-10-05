---
name: task-worker
description: |
  割り当てられたtaskを再読し、Git worktreeで実装、独立レビュー、必須検証、Draft PRとCI成功まで進める。
  `$task-session-launch`から起動された実装Taskで使う。
---

# Task Worker

タスク管理元の最新情報、起動promptの合意・許可範囲、直接依存と関連資料・規約を確認する。再開時は必要な情報を読み直す。
割り当てられたGit worktreeでConventionalな英語branchを作り、実装する。
レビュー前に自身の確定Task IDを確認する。Codexは`CODEX_THREAD_ID`、Claudeは起動元のID通知を用い、未確認ならレビューを開始せず通知を待つ。
候補をcommitしてから[task-review-cycle](../task-review-cycle/SKILL.md)を読み、独立レビューを受ける。
参照資料の相対パスは、そのSKILL.mdのディレクトリを基準に解決する。
親への通知や完了記録は扱わない。

## 修正と完了

編集中と修正時は影響箇所を検証する。Blockingと採用する任意改善をまとめて修正・commitし、同じreview TaskでLGTMまで続ける。Non-blockingの未対応だけでは再レビューしない。
最終検証やCIで候補を修正した場合も、新headを独立レビューする。全検証は修正のたびに繰り返さず、LGTM後の最終headでリポジトリ所定の必須検証を完了する。

そのheadを通常のpushで公開し、create-pr SKILL、なければPR templateと直近の慣例に従ってDraft PRを作成・更新する。
完了条件はPR headとreview済みheadの一致、そのheadの必須検証・独立LGTM・CI成功とする。
完了報告のGit・PR・CI状態は直近の確認結果に基づき、未追跡・失敗などを未確認のまま断言しない。
Ready化・mergeは別途依頼された場合だけ行い、その直前に現在のbaseとのmerge可否と意味的な競合を確認する。

## Review基点

最初のレビュー直前にbase branchをfetchし、そのtipを必要に応じて取り込む。そのSHAをreview baseに固定し、`<base SHA>...<head SHA>`と候補のpush状態・PR URLを渡す。

baseの進行だけでは取り込み・全検証・再レビューを繰り返さない。実際の競合や変更行・挙動の重複で上流を取り込んだ場合だけ、そのbase SHAへ基点を更新して必要な検証と再レビューを行う。
