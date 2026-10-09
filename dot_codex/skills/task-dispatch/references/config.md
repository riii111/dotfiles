# config.yaml

人が作成・編集する。task-dispatchは読むだけで書き換えない。

```yaml
owner: your-github-login       # 承認・レビューとして扱うGitHubアカウント
repos:                         # GitHubのリポジトリと、Codex projectのローカルパスの対応
  org/repo: /Users/you/src/org/repo
project:                       # 優先度・期限を読むGitHub Project。なければ省略
  owner: org
  number: 1
  priority_field: Priority     # 単一選択。選択肢の定義順を高い順とする
  due_field: Due               # 日付。近い順
sources:
  - name: example-epic         # 朝刊の見出しに使う案件名
    umbrella: org/repo#123     # umbrella issue。省略可
    kind: issue                # issue / improvement / investigation
    query: >-
      repo:org/repo is:issue is:open label:agent-ready author:your-github-login
limits:
  max_unreviewed_drafts: 3     # 未レビューのDraft PRがこの件数以上なら新規起動しない
  max_review_rounds: 3         # ownerのレビューで続行が必要になった回数の上限
  max_launches_per_run: 2      # 1回の実行で新規に起動する件数の上限
  max_investigations_per_run: 2  # 1回の実行で調査する件数の上限
  run_minutes: 30              # 1回の実行の時間枠
  task_hours: 24               # 起動からreview_readyまでの時間枠
```

- `repos`にないリポジトリのIssueは起動せず、`needs_decision`にする。
- `sources[].query`は`gh search issues`にそのまま渡す。リポジトリ・ラベルに加えて作成者を`owner`に絞り、人が開始を許した範囲だけを書く。
- `sources[].umbrella`を省略した発見元の項目は、朝刊の「案件なし」にまとめる。
- 起動の順は、`project`の優先度・期限と依存関係を先に適用し、同じ順位の中で`kind`の区分を使う。
- `max_review_rounds`は人のレビューの回数で、worker内のCodexレビューの往復は数えない。
- 上限の値は例。運用しながら人が調整する。
