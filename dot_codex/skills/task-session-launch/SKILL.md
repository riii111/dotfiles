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
   - `prompt`には作業順の要点を含め、詳細は`$task-worker`に従わせる。
     - 編集・指摘修正中は影響箇所を検証する。
       初回レビュー前にbase branchを一度fetchしてreview baseを固定し、commit済みheadをローカル固定SHA差分で独立レビューする。
     - LGTM後に所定の全検証を行い、review済みheadを通常のpushで公開してDraft PRを作成または更新する。
       PR headとの一致を確認してからCI成功まで確認する。
     - 最終検証またはCIでコードを直した場合は、新headを再レビューし、全検証・push・PR head確認・CIをやり直す。
3. `codex_app__create_thread`を一度呼ぶ。

## 制約

`clientThreadId`は`worktree`準備中の正常な結果として扱う。
`clientThreadId`が返っても`codex_app__create_thread`を重ねて呼ばない。
