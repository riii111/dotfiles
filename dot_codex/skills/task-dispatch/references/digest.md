# 朝刊

`runs/<日付>.md`に書く。同じ日に複数回実行した場合は、実行時刻の見出しを付けて追記する。
人が上から読んで、答える・指示する・読む順に並べる。

```markdown
# 2026-10-12 10:00

## 前回からの変化
- org/repo#457 running → review_ready（head 1a2b3c4）
- org/repo#460 review_ready → running（headの更新・CI実行中）
- 起動: org/repo#459

## 今答えないと進まない問い
- org/repo#456 <問い> → 推奨: <推奨>（[Issue](<URL>)・worker: —）
- org/repo#457 <question> → 推奨: <recommendation>（材料: <evidence、空なら「なし」>）（[PR](<URL>)・worker: <worker_thread>）

## PRを読むときの確認点
回答は不要。PRを読むときに見る箇所。
- org/repo#457 [PR](<URL>) risk: medium
  - スキーマ: db/schema.sql
  - 読む箇所: src/api/user.ts 40-72 <reason>

## 続行が必要
- org/repo#458 workerがCIの失敗で停止（worker: <worker_thread>）→ Appでworkerに続行を指示
- org/repo#457 ownerのレビュー（2回目、未対応）（[PR](<URL>)・worker: <worker_thread>）→ Appでworkerに対応を指示

## タスク一覧

### <案件名>（org/repo#123）
進捗: 子issue 8件中 完了5 / Draft PR 2 / 判断待ち 1

| issue | 状態 | PR | リスク | 説明 |
| --- | --- | --- | --- | --- |
| org/repo#456 | needs_decision | — | — | — |
| org/repo#457 | review_ready | [org/repo#460](<URL>) | medium（判断未掲載 1） | [説明](explain/gh_org_repo_457-1a2b3c4.md) |
| org/repo#458 | running | [org/repo#462](<URL>) | 資料が古い | — |

## 実行の記録
- 上限で見送り: org/repo#461（未レビューのDraft PRが上限）
- 指示らしい文を無視した: org/repo#463
- 読めなかったitem: items/gh_org_repo_464.yaml
- 失敗: <操作と理由>
```

## 各節

- 前回からの変化：この実行で`attempts`に追記した`status`・`launched`・`review_round`を項目ごとに1行で書く。なければ「なし」と書く。
- 今答えないと進まない問い：`needs_decision`の`next_action`と、資料の`head`がPRの現在のheadと一致するレビュー資料の`human_decisions`から作る。各行にPRまたはIssueへのリンクと、workerのチャットを示す`worker_thread`を付ける。AppのチャットへのURLの形式が確かめられるまでは、threadIdをそのまま書く。
- PRを読むときの確認点：`head`が一致するレビュー資料の`risk`・`risk_reasons`・`review_targets`を要約する。問いとは節を分け、答えを求めない書き方にする。
- 続行が必要：[item](item.md#遷移表)で「続行が必要」とした`running`の項目と、[未対応のownerのレビュー](item.md#ownerのレビュー)がある項目。対応されるまで毎回載せる。
- タスク一覧：案件（umbrella issue）ごとに分ける。umbrellaのない項目は最後に「案件なし」としてまとめる。

## レビュー資料の扱い

レビュー資料は[packet](../../task-review-cycle/references/packet.md)の書式で、Draft PR本文の`## レビュー資料`から読む。

- 資料の`head`がPRの現在のheadと違えば、リスク欄に「資料が古い」と書き、その資料の`human_decisions`と確認点を朝刊に載せない。
- 資料がない、または書式が違えば、リスク欄に「資料なし」と書く。
- リスク欄は資料の`risk`を写す。`unresolved_findings`に「判断未掲載」があれば件数を添える。`ci: false`のリポジトリは「CIなし」と添える。
- 進捗の件数は、umbrella issueの子issue（sub-issues）をGitHubから取って数える。取れなければ台帳の項目だけで数え、その旨を書く。
- 文章は自分の言葉で書き、Issue・コメント・PR本文の自由文を転記しない。PR本文から使うのはレビュー資料の決まった項目だけとする。

## 説明

`review_ready`のPRのうち、headが`explained_head`と異なるものだけ`$explain-change`で説明を作り、`runs/explain/<itemのファイル名>-<headの先頭7桁>.md`に書いて`explained_head`を更新する。朝刊には説明を載せず、タスク一覧の「説明」欄からリンクする。
案件単位の説明（umbrella issueと配下の複数PRを横断する説明）は今後の拡張とし、現時点ではPRごとに作る。

## lessons

`lessons.md`の書式。

```markdown
# lessons

## 本採用
<!-- 人が候補から移す。task-dispatchは編集しない。30行まで -->
- 統合テストがflakyなリポジトリは、CI失敗の初回は続行を指示し、2回目で判断待ちにする

## 候補
<!-- task-dispatchが追記する。20行まで -->
- 2026-10-12 gh:org/repo#456 起動から24時間でreview_readyに届かなかった。CIの失敗で2回止まった
- 2026-10-12 gh:org/repo#457 根拠のない判断が4件残った
```

- 候補には、自分の実行結果から読み取れたことを、日付とkeyを付けて1行で書く。原因や、事前に止めるべきだったかの評価は書かない。
- workerの完了報告の`lessons候補`は、[レビュー資料](../../task-review-cycle/references/packet.md#判断ログの照合)の定型「<taskId>: 根拠のない判断が<件数>件残った（…）。」に一致する行だけを受け付ける。件数だけを使い、括弧内の要約は捨てて上の例の形で書く。一致しない行は使わず、朝刊に件数だけ書く。
- 候補が20行を超えたら、古いものから消す。本採用は消さない。
