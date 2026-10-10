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
  max_launches_per_run: 2      # 1回の予定に載せる新規起動の上限
  max_investigations_per_run: 2  # 1回の実行で調査する件数の上限
  max_questions_per_plan: 3    # 1回の予定で聞く問いの上限
  run_minutes: 30              # 1回の実行の時間枠
  task_hours: 24               # 最後にrunningへ移してからreview_readyまでの時間枠
  notice_minutes: 90           # 予定を書いてから起動・送信できるまでの最短の間
```

- `repos`にないリポジトリのIssueは起動せず、`needs_decision`にする。
- `sources[].query`は`gh search issues`にそのまま渡す。リポジトリ・ラベルに加えて作成者を`owner`に絞り、人が開始を許した範囲だけを書く。
- 予定と報告の案件の見出しは`sources[].name`で、`umbrella`の最上位の親Issueへリンクする。`umbrella`を省略した発見元はリンクなしの見出しにする。
- 起動の順は、`project`の優先度・期限と依存関係を先に適用し、同じ順位の中で`kind`の区分を使う。
- `max_review_rounds`は人のレビューの回数で、worker内のCodexレビューの往復は数えない。
- `max_continues`は、最後に`review_ready`へ移した後（なければ起動後）の送信を理由ごとに数える。上限に達した後の停止は、続行を送らず人の判断待ちにする。
- 上限の値は例。運用しながら人が調整する。

## 実行の時刻

Scheduled Taskを3つ作り、どれも`~/agent-desk/`を作業ディレクトリにする。時刻は例。

| 時刻 | 指示 | すること |
| --- | --- | --- |
| 平日 17:30 | `$task-dispatch 予定` | 今夜の予定を書く |
| 平日 20:00 | `$task-dispatch 起動` | 予定どおりに起動・続行する |
| 平日 6:00 | `$task-dispatch 報告` | 予定との違いを報告する |

予定から起動までの間は、ユーザーが予定を読んで止める時間になる。`notice_minutes`と`run_minutes`の和より長く空け、予定を読める時刻に置く。手動で再実行するときも、同じ指示を使う。
