---
name: task-worker
description: |
  オーケストレーションで割り当てられた子セッションのタスクを、再読、専用git worktreeでの実装、全検証、draft PR作成、review side chatとの修正反復、Ready化まで進める。
  task-orchestrationから起動された実装タスク、停止したレビュー反復の再開、明示的に許可されたmergeまでの進行に使う。
---

# Task Worker

担当タスクを実装し、独立したreview side chatからLGTMを得てPRをReadyにする。外部プログラムへreview状態を保存しない。

## 入力

- オーケストレーションID
- task IDとタスク管理元
- repositoryとbase
- merge方針。既定は手動merge

不足値は親セッションのGoalと会話履歴から補う。repository、base、オーケストレーションID、task IDを確定できなければ推測せずユーザーへ返す。

## 現在状態を復元する

開始時と「続けて」での再開時は、会話上の進捗を前提にせず次を行う。

1. タスク管理元から担当タスクの最新本文、依存タスク、添付資料、コメントを再読する。依存タスクの成果物と現在のrepository規約も読む。
2. `task-orchestration` SKILLのディレクトリにある状態管理ツールを実行する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py context <orchestration-id>
```

3. `sessions.tasks[<task-id>].child_thread_id`を自分の通知先セッションIDとして取得する。taskが未登録、予約中、またはIDが空なら停止する。会話から推測したIDで代用しない。
4. `pull_request`があれば`gh pr view`でrepository、番号、base、draft状態、head SHA、checks、merge状態を確認する。ローカルworktreeは`git worktree list`とbranchから探す。
5. PRなしなら実装工程、draft PRならreview工程から再開する。Readyならmerge方針を確認し、手動mergeなら待機し、明示的な自動merge許可があればLGTMの証拠、最新headの全検証、必須checksを再確認してmerge工程へ進む。mergedなら完了を報告する。closedか状態が矛盾する場合は自動復旧しない。

これにより、通知漏れで停止してもPRの現在状態から再開する。

## 実装工程

1. 指定baseの最新状態を確認する。既存の担当worktreeがなければ、目的を表すconventionalな英語branch名を決め、task IDやissue番号を含めず、`git worktree add`で専用worktreeを作る。Codex管理のworktreeは使わない。
2. 適用される規約、仕様、近傍実装を読む。直接の変更箇所だけでなく、呼び出し元、公開境界、永続化形式、設定、テスト、失敗経路など二次・三次影響まで調べる。
3. 実装し、変更を小さく意味的にまとまったConventional Commitsへ分ける。各commitに無関係な変更を混ぜない。
4. repository所定のformat、lint、静的検査、test、buildをすべて通す。失敗を未確認のままdraft PR作成へ進まない。
5. PR templateと直近の慣例に従ってdraft PRを作る。PR本文へオーケストレーター固有のtask IDやmarkerを書かない。
6. PR作成直後に次を一回実行する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_state.py record-pr <orchestration-id> \
  --task-id <task-id> \
  --repository <owner/repository> \
  --number <pr-number>
```

`record-pr`が失敗してもPRを作り直さない。作成済みPRとエラーをユーザーへ返す。

## review side chatを一度だけ作る

draft PRと子セッションIDを確認してから、現在の子セッションを`fork_thread`のsame-directoryで一度だけ分岐する。作成したreview thread IDを会話内に明記し、`[Review] <task-id>: <PR title>`へ変更する。

既存のreview thread IDが会話履歴にあれば新規作成せず再利用する。存在が不明なときは`list_threads`と`read_thread`で同じtask ID・PRのside chatを探す。一意に確認できなければ、重複作成せずユーザーへ確認する。

作成後、`send_message_to_thread`で次の依頼を同じreview side chatへ送る。

```text
$code-reviewを使い、<owner/repository>のPR #<number>をbase <base>との差分でsingle reviewしてください。
担当はtask <task-id>、タスク管理元は<task-source>です。最新のタスク本文と依存タスクを再読してください。
repository規約、タスク資料、呼び出し元やテストを確認し、code-review SKILLの形式で指摘を出し切ってください。
指摘がなければLGTMとしてください。
結果の先頭に`Reviewed head: <head SHA>`を付けてください。
結果は必ずsend_message_to_threadで子セッション <child-thread-id> へ送ってください。
PRへのコメント投稿、修正、mergeは行わないでください。
```

review AIには既存の`code-review` SKILLを使わせる。レビュー基準をこのSKILLや依頼文へ複製しない。ユーザーは子セッションとreview side chatのどちらにも追加指示でき、その最新指示を以後の反復へ反映する。

## 指摘を反復する

review AIは確認したhead SHAと、`Blocking`、`Non-blocking`、必要な場合の`既存パターンとの差異`、または`LGTM`を、指定された子セッションへ`send_message_to_thread`で送る。送信に失敗した場合はreview side chatに結果と失敗を残し、送信済みと扱わない。

指摘を受けたら次を行う。

1. 指摘を現在のPR差分とrepository realityに照らして確認する。ユーザーが方針を変えた場合はその指示を優先する。
2. 妥当な指摘を修正し、必要なtestを追加する。
3. repository所定の全検証を再実行し、小さなcommitにしてpushする。
4. 新しいhead SHA、対応内容、検証結果を添え、`send_message_to_thread`で既存のreview thread IDへ再レビューを依頼する。新しいside chatを作らない。
5. review AIは更新後のbase差分全体を同じ`code-review` SKILLで再確認し、同じ子セッションIDへ結果を送る。

review結果を待つ間も、ユーザーから届いた指示へ応答できる状態を保つ。

## LGTM後

LGTMを受け取ったら、review対象のhead SHAから追加commitがないこと、PRがdraftであること、最新headの全検証と必須checksが成功していることを確認する。条件を満たしたら`gh pr ready`でReady for reviewへ変更する。

mergeは手動を既定とする。「自動merge可」など曖昧な過去の慣例では許可とみなさない。ユーザーまたは親Goalがこのrepositoryとタスクについて明示的に許可した場合だけ、LGTM、最新headの全検証、必須checks成功を再確認してmergeする。許可がなければReady化と結果報告で終了する。

## 停止条件

次の場合は破壊的な復旧やside chatの再作成をせず、判明した状態をユーザーへ返す。

- task、子セッション、PRの対応が不明または矛盾している
- worktreeやbranchの所有関係が不明である
- review side chatが存在する可能性を排除できない
- PRがclosed、競合中、または意図しないbaseへ向いている
- 検証失敗、必須check失敗、review結果の通知失敗が残っている
- merge許可の範囲が明示されていない
