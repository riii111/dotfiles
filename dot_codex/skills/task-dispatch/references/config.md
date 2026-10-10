# config.yaml

人が作成・編集し、task-dispatchは読み取り専用とする。

```yaml
project:                       # 優先度・期限を読むGitHub Project。なければ省略
  org: org                    # GitHub Projectを持つ組織
  number: 1
  priority_field: Priority     # 単一選択。選択肢の定義順を高い順とする
  due_field: Due               # 日付。近い順
sources:
  - name: example-epic         # 予定と報告の見出しに使う案件名
    umbrella: org/repo#123     # umbrella issue。省略可
    query: >-
      repo:org/repo is:issue is:open label:agent-ready author:your-github-login
limits:
  max_waiting_reviews: 3       # レビュー待ちのPRがこの数以上なら新しく始めない
  max_continues: 2             # 同じ理由でworkerへ続行を送る回数の上限
  max_questions_per_plan: 3    # 1回の予定で聞く問いの上限
  run_minutes: 30              # 1回の実行の時間枠
schedule:
  plan_at: "17:00"             # Calendarがオフの日と、退勤時刻の返事がない日に予定を作る時刻
calendar:
  enabled: false               # trueで、朝に今日の予定から退勤予定と不在を読む
  leave_title: 退勤             # 退勤予定とみなす予定の名前
```

- `sources[].query`は`gh search issues`にそのまま渡す。
  リポジトリ・ラベルに加えて作成者を自分のアカウントに絞り、人が開始を許した範囲だけを書く。
- `sources[].name`と`umbrella`の表示方法は[予定と報告の書き方](digest.md#書き方)に従う。
- `project`による優先順は[今夜の予定を作成する](plan.md#今夜の予定を作成する)に従う。
- `max_continues`の数え方と上限到達時の扱いは[既存workerへの続行](continue.md)に従う。
- 新規起動の数の決め方は[新規起動する件数](launch.md#新規起動する件数)に書く。
- 上限と時刻の値は例。運用しながら人が調整する。
- `calendar.enabled`がfalseなら、退勤時刻を聞かず、毎日`schedule.plan_at`に予定を作る。休みも読まない。

## 実行の時刻

人が作るScheduled Taskは2つで、どちらも`~/agent-desk/`を作業ディレクトリにする。時刻は例。

| 時刻 | 指示 | すること |
| --- | --- | --- |
| 平日 6:00 | `$task-dispatch 報告` | 予定との違いを報告し、今日の予定作成の実行を登録する |
| 平日 22:00 | `$task-dispatch 起動` | 続行を送り、OK済みで残った項目を起動する |

予定作成の実行（`$task-dispatch 予定`）は、task-dispatchが[前日以前の後始末と今日の予定登録](schedule.md#前日以前の後始末と今日の予定登録)で登録し、使い終えたら消す。
予定作成の実行は退勤の1時間前で、ユーザーが在席してスレッドに返事をできる時刻とする。
手動で再実行するときも、同じ指示を使う。

## 試運転で確かめること

会社のMacで在席中に動かし、次を確かめてから`calendar.enabled`をtrueにし、無人の時刻へ移す。

1. Calendarのプラグインで、退勤予定と不在（outOfOffice）を読めるか。
2. Scheduled Taskから毎回新しいスレッドを作って動かせるか。そのスレッドへの返事で続きが動くか。
3. スレッドが自分をアーカイブできるか。
4. 実行から`automation_update`でScheduled Taskを作成・更新・削除できるか。
5. workerを起動したスレッドとは別のスレッドから続行を送り、workerが進むか。
6. `auto_review`のもとで、サンドボックス外の実行（`harnexus-task`など）が無人でも止まらないか。
