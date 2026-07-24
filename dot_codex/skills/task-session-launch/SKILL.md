---
name: task-session-launch
description: |
  task-orchestrationの親FSMが返した子セッション作成操作を予約からタイトル設定まで実行する。reserve_sessionからset_thread_titleまでのactionを引き継いだときに使う。
---

# Task Session Launch

子セッション作成の外部操作だけを担当する。対象taskや操作順を独自に選ばず、`orchestration_transition.py`のaction、details、allowed eventsを正本にする。

## 一操作ずつ進める

- `reserve_session`: `orchestration_state.py reserve-session`を実行する。
- `create_thread`: 許可repositoryの保存済みprojectを一意に確認する。同じtask IDとaction tokenを持つ未記録Threadを先に探し、存在しない場合だけlocal環境で一回作成する。取得したrepository、Thread ID、host、project、checkoutを直ちにeventへ入れる。
- `verify_thread`: 作成済みThreadを再読し、repository、host、project、checkoutの観測値をeventへ入れる。
- `record_session`: `orchestration_state.py record-session`を実行する。
- `set_thread_title`: Threadを`[<task-id>] <task title>`へ変更する。

各操作後は、FSM出力のschemaどおりevent JSONを作り、検証・保存する。

```text
python3 <task-orchestration-skill-directory>/scripts/orchestration_transition.py apply-event <orchestration-id> \
  --source-revision <task-source-revision> \
  --event-file <event-json-path>
```

返された`executor_skill`が自分なら続け、それ以外は`task-orchestration`へ戻す。eventの許可条件と次actionは状態遷移ツールへ任せる。

## 子セッションへ渡すGoal

タイトルとGoalへtask IDを入れ、action tokenを再開識別子としてGoal末尾へ添える。Goalには次を含める。

- task sourceから最新本文と直接依存を再読する
- 指定baseから通常の`git worktree`を作る
- 呼び出し元、公開境界、永続化形式、設定、テスト、失敗経路まで調べる
- task IDを含まないconventionalな英語branch名を使う
- 小さなConventional Commitsで実装し、repository所定の全検証を通す
- Draft PRを作り、`orchestration_state.py record-pr`で対応付ける
- 子セッション用SKILLと、明示された完了方針
- FSM detailsの`dependency_completion_notes`

model指定がなければ原則として`gpt-5.6-luna` + `xhigh`を使い、設計・仕様判断が必要なtaskだけ`gpt-5.6-sol` + `medium`を使う。空のNoteを渡さず、PR本文へ管理用task IDやmarkerを書かない。
