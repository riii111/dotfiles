---
name: task-orchestration
description: |
  オーケストレーションIDに紐づくタスク群を毎回読み直し、PRのmergeと依存関係から次に開始できるタスクを選び、通常の独立したCodex子セッションを重複なく作成する。
  最初のタスク開始、merge通知後の再開、開始済み・依存待ちタスクの整理に使う。
---

# Task Orchestration

一回の実行で、次に同時開始するタスクを選ぶ。subagent、`fork_thread`、Codex管理のworktreeは使わない。

## 入力と共有データ

オーケストレーションID、base、正の整数の最大並列数を必須入力とする。ブリッジのmerge情報、子セッション用SKILL、merge方針は任意とし、後二つの既定は「利用なし」「手動merge」とする。必須入力を過去の会話からも確定できなければ、既定branchや並列数を推測せず「判断が必要」として返す。

IDは先頭がASCII小文字または数字、残りがASCII小文字、数字、ハイフンだけであることを確認する。

設定は、絶対パスの`XDG_CONFIG_HOME`があればその配下、なければ`$HOME/.config`から読む。

```text
<config-base>/codex-task-orchestrator/config.toml
```

設定schemaはRust実装を優先する。

```toml
[orchestrations.<orchestration-id>]
parent_thread_id = "parent-thread-id"
repository = "owner/repository"
task_source = "task-source"
```

状態の基点は、絶対パスの`XDG_STATE_HOME`、なければ`$HOME/.local/state`とする。

```text
<state-base>/codex-task-orchestrator/<orchestration-id>/sessions.json
<state-base>/codex-task-orchestrator/<orchestration-id>/merges.json
```

セッション対応表はこのSKILLだけが更新する。task ID、本文、状態、依存関係、PR番号、host IDを追加しない。

```json
{
  "version": 1,
  "parent_thread_id": "parent-thread-id",
  "tasks": { "TASK-1": { "child_thread_id": "child-thread-id" } }
}
```

merge処理記録は参照だけにする。

```json
{
  "version": 1,
  "pull_requests": {
    "123": {
      "task_id": "TASK-1",
      "merge_commit": "commit-sha",
      "parent_notification": "pending",
      "local_notification": "sent"
    }
  }
}
```

通知状態は`parent_notification`: `pending|delivered`、`local_notification`: `not_sent|sent`だけを受け入れる。存在しない状態ファイルは空とし、存在するファイルのJSON、version、必須値が不正なら修復せず停止する。

## 開始するタスクを選ぶ

1. 設定とセッション対応表を読む。ID未登録、設定不正、空のtask source、`owner/repository`形式でないrepositoryは停止条件とする。対応表のversion、空でないthread ID、設定と同じ`parent_thread_id`を確認する。取得できるなら現在の親thread IDとも照合する。対応表がなければ、初回であることを保持したうえで空の`tasks`として初期化する。
2. `task_source`に対応するコネクタまたはCLIから、全タスクのID、最新本文、直接依存、現在状態、利用可能な状態履歴、優先順位または並び順を毎回読み直す。ページングと依存先を省略しない。キャッシュや会話への転記では判断しない。
3. 重複ID、本文欠落、存在しない依存先、自己依存、循環依存、取得失敗が一つでもあれば、子セッションを作らず「判断が必要」とする。
4. 下記の順で完了証拠を集める。証拠の食い違い、認証・通信失敗、不完全な応答は「未完了」と推測せず停止する。
   1. ブリッジのmerge情報からtask ID、PR番号、PR URL、merge commitを検証する。
   2. `merges.json`の全PRを読み、通知状態にかかわらずtask IDとmerge commitを得る。
   3. ブリッジ情報なしで起動した場合は、対応表にある全task IDのPRを`gh`で直接確認する。必要な証拠が足りない場合も確認する。
   4. `gh`ではopen、closed、mergedを漏れなく調べ、PR本文の独立した`Task-ID: <task-id>`行を完全一致で照合し、`mergedAt`とmerge commitがあるPRだけを完了とする。
5. オーケストレーション開始前から完了していたタスクだけは、タスク管理元の完了状態を初期値に使う。初回時点、状態履歴、親セッションの記録のいずれでも開始前と証明できなければ使わない。後から管理元だけが完了になったタスクをmergeなしで完了にせず、開始前か不明ならユーザーへ返す。この初期値を対応表へ保存しない。
6. merge証拠のtask IDが対応表にない、repositoryが異なる、同じPRのtask IDが食い違う場合は停止する。
7. 次を計算する。

```text
completed = merge証拠または開始前完了の証拠があるタスク
launched_uncompleted = 対応表にありcompletedではないタスク
unstarted = completedでも対応表登録済みでもないタスク
ready = unstartedのうち全依存taskがcompletedであるタスク
available_slots = max(0, maximum_parallelism - launched_uncompletedの数)
```

8. `ready`から空き枠までを同時に開始するタスクとして選ぶ。タスク管理元の優先順位・並び順を優先し、同順位または指定なしならtask ID昇順にする。残りは「並列数上限」として見送る。
9. 対応表にあるタスクは、子セッションの状態にかかわらず再作成しない。記録済みthreadが見つからなくても削除・再作成せず「判断が必要」とする。

## 子セッションを作る

選んだ各タスクについて、必ず一つずつ次を行う。

1. `list_projects`でrepositoryに対応する保存済みprojectを一意に特定する。候補なし・複数候補なら停止する。
2. 対応表を再読し、task IDが未登録で親IDも不変であることを確認する。
3. `create_thread`を一回だけ呼ぶ。project targetの`environment`は`local`とし、modelとthinkingは明示指定がある場合だけ渡す。promptには下記Goalを使う。
4. 戻り値の`threadId`をchild thread IDとする。`clientThreadId`しかなければ推測せず停止する。
5. 作成成功後すぐ、既存taskを保持して対応表へIDを追加する。同じディレクトリの一時ファイルへ有効なJSONを書いて置換し、保存完了後に次のタスクへ進む。
6. `set_thread_title`で`[<task-id>] <task title>`へ変更する。失敗時は登録を残して以降の作成を止める。

作成後の保存に失敗した場合は、未記録のthread IDを明記して停止し、再作成しない。子セッション自身がGoalに従い`git worktree`を作る。

## 子セッションへ渡すGoal

具体値を埋め、タイトルとGoalの両方にtask IDを含める。

```text
Goal: <task-id> <task title>を完了する。
タスク管理元: <task-source>
対象リポジトリ: <repository>
base: <base>

- <task-id>の最新本文と依存タスクをタスク管理元から最初に再読する。
- 指定baseからgit worktreeで専用の作業場所を作る。Codexのworktree機能は使わない。
- 呼び出し元、公開境界、テスト、設定、失敗経路など二次・三次影響まで調べてから実装する。
- branch名は目的を表すconventionalな英語名にし、issue番号やtask IDを含めない。
- commitはConventional Commitsに従い、小さく意味的にまとめる。
- リポジトリ所定のlint、test、型検査、buildなど全検証を通す。
- 検証後にdraft PRを作り、PR本文の独立した行へ`Task-ID: <task-id>`と記載する。
- 子セッション用SKILL: <SKILL名、または利用なし>。
- merge方針: <手動merge、または明示的に許可された条件付き自動merge>。
```

タスク本文を転記しても再読を省略させない。自動mergeは対象repositoryへの明示的な許可と条件がある場合だけ記載する。

## 結果とfixture

作成したtask・タイトル・thread ID、完了taskと根拠、見送ったtaskと理由、依存待ちtaskと未完了依存、対応表の保存先を返す。部分失敗時は保存済み・未保存を分け、作成済みthread IDをすべて示す。

作成対象がない確定状態は`開始可能なタスクなし`とする。入力不足、取得失敗、schema不正、依存・完了証拠の矛盾、project・threadの特定不能は`判断が必要`とする。

実threadを作らない検証では、最大並列数2、`A: []`、`B: []`、`C: [A,B]`を使い、初回はA・Bを同時に選び、Aだけmerge後もCはB待ち、A・B merge後はCを次に選ぶことを確認する。A・B登録済みの再実行では子を増やさず、未mergeなら`開始可能なタスクなし`とする。別fixture`D: [MISSING]`は`判断が必要`とする。各作成成功直後のID保存と、Goalのworktree、二次・三次影響、branch、commit、全検証、draft PR、`Task-ID`も確認する。
