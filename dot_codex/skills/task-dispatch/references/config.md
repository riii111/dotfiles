# config.yaml

人が作成・編集する。task-dispatchは読むだけで書き換えない。

```yaml
owner: your-github-login       # 承認・レビューとして扱うGitHubアカウント
repos:                         # 起動してよいリポジトリ
  org/repo:
    path: /Users/you/src/org/repo  # Codex projectのローカルパス
    ci: true                   # CIのないリポジトリだけfalse
project:                       # 優先度・期限を読むGitHub Project。なければ省略
  owner: org
  number: 1
  priority_field: Priority     # 単一選択。選択肢の定義順を高い順とする
  due_field: Due               # 日付。近い順
sources:
  - name: example-epic         # 予定と報告の見出しに使う案件名
    umbrella: org/repo#123     # umbrella issue。省略可
    kind: issue                # issue / improvement / investigation
    query: >-
      repo:org/repo is:issue is:open label:agent-ready author:your-github-login
limits:
  max_unreviewed_drafts: 3     # 未レビューのDraft PRがこの件数以上なら新規起動しない
  max_review_rounds: 3         # ownerのレビューの往復回数の上限
  max_continues: 2             # 同じ理由でworkerへ続行を送る回数の上限
  max_investigations_per_run: 2  # 1回の実行で調査する件数の上限
  max_questions_per_plan: 3    # 1回の予定で聞く問いの上限
  run_minutes: 30              # 1回の実行の時間枠
  task_hours: 24               # 最後にrunningへ移してからreview_readyまでの時間枠
schedule:
  plan_at: "17:00"             # Calendarがオフの日と、退勤時刻の返事がない日に予定を作る時刻
calendar:
  enabled: false               # trueで、朝に今日の予定から退勤予定と不在を読む
  leave_title: 退勤             # 退勤予定とみなす予定の名前
```

- `repos`にないリポジトリのIssueは起動せず、`needs_decision`にする。
- `sources[].query`は`gh search issues`にそのまま渡す。リポジトリ・ラベルに加えて作成者を`owner`に絞り、人が開始を許した範囲だけを書く。
- 予定と報告の案件の見出しは`sources[].name`で、`umbrella`の最上位の親Issueへリンクする。`umbrella`を省略した発見元はリンクなしの見出しにする。
- 起動の順は、`project`の優先度・期限と依存関係を先に適用し、同じ順位の中で`kind`の区分を使う。
- `max_review_rounds`は人のレビューの回数で、worker内のCodexレビューの往復は数えない。
- `max_continues`は、最後に`review_ready`へ移した後（なければ起動後）の送信を理由ごとに数える。上限に達した後の停止は、続行を送らず人の判断待ちにする。
- 新規起動の数の決め方は[量](launch.md#量)に書く。
- 上限と時刻の値は例。運用しながら人が調整する。
- `calendar.enabled`がfalseなら、退勤時刻を聞かず、毎日`schedule.plan_at`に予定を作る。休みも読まない。

## 実行の時刻

人が作るScheduled Taskは2つで、どちらも`~/agent-desk/`を作業ディレクトリにする。時刻は例。

| 時刻 | 指示 | すること |
| --- | --- | --- |
| 平日 6:00 | `$task-dispatch 報告` | 予定との違いを報告し、今日の予定の回を登録する |
| 平日 22:00 | `$task-dispatch 起動` | 続行を送り、OK済みで残った項目を起動する |

予定の回（`$task-dispatch 予定`）は、task-dispatchが[1日の段取り](schedule.md#1日の段取り)で登録し、使い終えたら消す。どの回もScheduled Taskが毎回新しいスレッドを作り、通知はCodex Appに任せる。予定の回は退勤の1時間前で、ユーザーが在席してスレッドに返事をできる時刻とする。手動で再実行するときも、同じ指示を使う。

## 試運転で確かめること

会社のMacで在席中に動かし、次を確かめてから`calendar.enabled`をtrueにし、無人の時刻へ移す。

1. Calendarのプラグインで、退勤予定と不在（outOfOffice）を読めるか。
2. Scheduled Taskから毎回新しいスレッドを作って動かせるか。そのスレッドへの返事で続きが動くか。
3. スレッドが自分をアーカイブできるか。
4. 実行から`automation_update`でScheduled Taskを作成・更新・削除できるか。
5. workerを起動したスレッドとは別のスレッドから続行を送り、workerが進むか。
6. `auto_review`のもとで、サンドボックス外の実行（`harnexus-task`など）が無人でも止まらないか。
