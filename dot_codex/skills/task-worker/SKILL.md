---
name: task-worker
description: |
  割り当てられたtaskを再読し、Git worktreeで実装、独立レビュー、必須検証、Draft PRとCI成功まで進める。
  `$task-session-launch`から起動された実装Taskで使う。
---

# Task Worker

開始時は、`prompt`で渡されたタスク管理元から開始対象のtask情報を読む。
直接依存、成果物、添付資料、リポジトリ規約を確認する。
管理元にない合意と許可範囲は起動promptに従う。SKILLや参照資料の相対パスは、そのSKILL.mdのディレクトリを基準に解決する。
再開時に必要なら同じタスク管理元を読み直す。
割り当てられたGit worktreeで目的を表すConventionalな英語branchを作り、実装する。
実装後は候補をcommitし、[task-review-cycle](../task-review-cycle/SKILL.md)を読んでローカル固定SHA差分の独立レビューを受ける。
親への通知や完了記録は扱わない。

## 修正と完了

編集中とレビュー指摘の修正時は、影響箇所のテスト・検査を行う。
Blocking と採用する任意改善は可能な範囲でまとめて修正し、新しい候補をcommitして同じreview Taskへ再レビューを依頼する。
LGTMまで続ける。Non-blockingは任意とし、未対応だけで再レビューを繰り返さない。
修正のたびに全検証は繰り返さない。最終検証やCIで候補を修正した場合も、新headに影響検証と独立レビューを行う。

独立LGTM後、最終候補でリポジトリ所定の必須検証（format・lint・test・buildなど）を行う。
通過したreview済みheadを通常のpushで公開し、リポジトリのcreate-pr SKILL、なければPR templateと直近の慣例に従ってDraft PRを作成または更新する。
PR headがreview済みheadと一致することを確認してから、CI成功まで確認する。
最終PR headでは必須検証、独立LGTM、CI成功をそろえる。
Ready化・mergeは別途依頼された場合だけ行う。

## Review基点

最初の独立レビューを始める直前にbase branchを一度だけfetchし、その時点のtipを必要に応じて取り込む。
そのexact SHAを全レビューのreview baseとして固定する。
各review Taskへ`<review base SHA>...<head SHA>`を渡す。
レビュー候補のpush状態とPR URL（未作成ならその旨）も伝える。

review開始後にbase branchが進んだことだけを理由に、取り込み・全検証・再reviewを繰り返さない。
Ready化・mergeが別途依頼された場合は、その直前に現在のbaseとのmerge可否と意味的な競合を確認する。
実際の競合、または変更行・挙動の重複がある場合だけbaseを取り込み、取り込んだbaseのSHAを新しいreview基点として必要な検証と再reviewを行う。
無関係なbase進行なら、固定したreview結果とheadのchecksを維持する。
