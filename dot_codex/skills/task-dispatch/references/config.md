# config.yaml

人が作成・編集する。task-dispatchは読むだけで書き換えない。

```yaml
owner: your-github-login       # 承認・レビュー指摘として扱うGitHubアカウント
project:                       # 優先度・期限を読むGitHub Project。なければ省略
  owner: org
  number: 1
  priority_field: Priority
  due_field: Due
sources:
  - name: example-epic         # 朝刊の見出しに使う案件名
    umbrella: org/repo#123     # umbrella issue。案件ごとの見出しと進捗に使う
    kind: issue                # issue / improvement / investigation
    query: >-
      repo:org/repo is:issue is:open label:agent-ready
limits:
  max_unreviewed_drafts: 3     # review_readyがこの件数以上なら新規起動しない
  max_review_rounds: 3         # 1項目でレビュー指摘への対応を送る回数の上限
  max_launches_per_run: 2      # 1回の実行で新規に起動する件数の上限
  run_minutes: 30              # 1回の実行の時間枠
  task_hours: 24               # 起動からreview_readyまでの時間枠
```

- `sources[].query`は`gh search issues`にそのまま渡す。対象を、人が開始を許した範囲（リポジトリ・ラベル・作成者）に絞って書く。
- `sources[].umbrella`は省略できる。省略した発見元の項目は、朝刊の「案件なし」にまとめる。
- `kind`は起動の優先順で使う。同じ`kind`の中の順位は`project`の優先度・期限で決まる。
- 上限の値は例。運用しながら人が調整する。
