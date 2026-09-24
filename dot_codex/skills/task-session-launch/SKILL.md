---
name: task-session-launch
description: |
  開始対象taskのCodex TaskをGit worktreeで作成し、タイトルと具体的な`prompt`を設定する。
  `$task-orchestration`から開始対象を受け取ったときに使う。
---

# Task Session Launch

## 手順

1. `codex_app__list_projects`を一度呼び、repositoryに対応する`projectId`を決める。
2. 次の内容で`codex_app__create_thread`の入力を組み立てる。
   - Git repositoryでは`target.environment.type`を`worktree`にする。
   - 通常はprojectのdefault branchからGit worktreeを作るため、`target.environment.startingState`を指定しない。
   - ユーザーが開始branchを明示した場合だけ、`target.environment.startingState`の`type`を`branch`にし、`branchName`をそのbranchにする。
   - `title`を`Impl <identifier>`にする。
   - `<identifier>`にはユーザーの入力とタスク管理元から対象を区別できる短い表記を選ぶ。
   - `title`にPR titleやtask titleを含めない。
   - `model`を`gpt-6-luna`、`thinking`を`xhigh`にする。
   - ユーザーがmodelまたはreasoning effortを明示した場合だけ、対応する値をその指定で置き換える。
   - `prompt`にタスク管理元、開始対象、親orchestration Task ID（指定されている場合）を含める。
   - `prompt`で`$task-worker`を使い、リポジトリ規約を読んで割り当てられたGit worktreeで実装するよう依頼する。
   - `prompt`には次の作業順を番号付きで示す。
     1. 編集中は影響箇所のテスト・検査を行う。
     2. 最初の独立レビュー前にbase branchを一度だけfetchする。
        そのtip SHAを全レビューのreview baseに固定する。
        必要ならtipを取り込んでから候補をcommitし、独立レビューを依頼する。
        依頼にはworker checkout、`<review base SHA>...<head SHA>`、候補のpush状態、PR URL（未作成なら明記）を含める。
     3. 指摘をまとめて修正し、影響検証後に新headをcommitして同じreview Taskへ再レビューを依頼する。
        LGTMまで繰り返し、各回に全検証やpushを要求しない。
     4. LGTM後、最終headで所定の全検証を行う。
        コードを修正した場合は新headを影響検証・独立レビューし、LGTM後に全検証をやり直す。
     5. 検証を通過したreview済みheadを通常のpushで公開し、Draft PRを作成または更新する。
        PR headがreview済みheadと一致することを確認してからCI成功まで確認する。
        CIでコードを修正した場合は、手順3から繰り返す。
   - review開始後にbase branchが進んでも、それだけでは変更を取り込まない。
     現在のbaseとの実際の競合または意味的重複がある場合だけ取り込み、必要な検証と再レビューを行う。
3. `codex_app__create_thread`を一度呼ぶ。

## 制約

`clientThreadId`は`worktree`準備中の正常な結果として扱う。
`clientThreadId`が返っても`codex_app__create_thread`を重ねて呼ばない。
