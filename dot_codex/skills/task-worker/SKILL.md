---
name: task-worker
description: |
  割り当てられたtaskを再読し、Git worktreeで実装、独立レビュー、全検証、Draft PRとCI成功まで進める。
  `$task-session-launch`から起動された実装Taskで使う。
---

# Task Worker

開始時は、`prompt`で渡されたタスク管理元から開始対象のtask情報を読む。
直接依存、成果物、添付資料、リポジトリ規約を確認する。
再開時に必要なら同じタスク管理元を読み直す。
割り当てられたGit worktreeで目的を表すConventionalな英語branchを作り、実装する。
実装後は候補をcommitし、`$task-review-cycle`でローカル固定SHA差分の独立レビューを受ける。
指摘が解消されLGTMになるまで同じreview Taskで続ける。
親への通知や完了記録は扱わない。

## 検証

編集中とレビュー指摘の修正時は、影響箇所のテスト・検査を行う。
指摘は可能な範囲でまとめて修正し、新しい候補をcommitして同じreview Taskへ再レビューを依頼する。
修正のたびに全検証は繰り返さない。

独立LGTM後、最終候補で所定のformat・lint・test・buildを行う。
通過したreview済みheadを通常のpushで公開し、PR templateと直近の慣例に従ってDraft PRを作成または更新する。
PR headがreview済みheadと一致することを確認してから、CI成功まで確認する。

最終検証またはCIでコードを修正した場合は、新headに影響検証と独立レビューを行う。
LGTM後にそのheadのformat・lint・test・buildを完了してから通常のpushを行う。
PR headとの一致を確認してCIを再実行する。
最終PR headでは必須検証、独立LGTM、CI成功をそろえる。

## Review基点

最初の独立レビューを始める直前にbase branchを一度だけfetchし、その時点のtipを必要に応じて取り込む。
そのexact SHAを全レビューのreview baseとして固定する。
各review Taskへ`<review base SHA>...<head SHA>`を渡す。
レビュー候補のpush状態とPR URL（未作成ならその旨）も伝える。

review開始後にbase branchが進んだことだけを理由に、取り込み・全検証・再reviewを繰り返さない。
Ready化・merge直前に現在のbaseとのmerge可否と意味的な競合を確認する。
実際の競合、または変更行・挙動の重複がある場合だけbaseを取り込み、必要な検証と再reviewを行う。
無関係なbase進行なら、固定したreview結果とheadのchecksを維持してmergeへ進む。
