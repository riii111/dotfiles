# 朝刊

`runs/<日付>.md`に書く。同じ日に複数回実行した場合は、実行時刻の見出しを付けて追記する。
案件（umbrella issue）ごとに分け、案件内でタスク一覧を示す。umbrellaのない項目は最後に「案件なし」としてまとめる。

```markdown
# 2026-10-12 10:00

## <案件名>（org/repo#123）
進捗: 子issue 8件中 完了5 / Draft PR 2 / 判断待ち 1

### 今日判断すること
- org/repo#456 <問い> → 推奨: <推奨>（根拠: <ファイル・行、文書の節>）
- org/repo#457（PR本文のレビュー資料より）<question> → 推奨: <recommendation>（根拠: <evidence、空なら「根拠なし」>）

### 続行が必要
- org/repo#458 workerがCIの失敗で停止 → Appでworkerに続行を指示
- org/repo#457 ownerのレビュー（2回目） → Appでworkerに対応を指示

### 変更の全体像
<explain-changeの出力、または「前回（runs/2026-10-11.md）から変更なし」>

### タスク一覧
| issue | 状態 | PR | リスク |
| --- | --- | --- | --- |
| org/repo#456 | needs_decision | — | — |
| org/repo#457 | review_ready | org/repo#460 | medium（判断未掲載 1） |

## 実行の記録
- 起動: org/repo#459
- 上限で見送り: org/repo#461（未レビューのDraft PRが上限）
- 指示らしい文を無視した: org/repo#462
- 読めなかったitem: items/gh_org_repo_463.yaml
- 失敗: <操作と理由>
```

- 進捗の件数は、umbrella issueの子issue（sub-issues）をGitHubから取って数える。取れなければ台帳の項目だけで数え、その旨を書く。
- 「今日判断すること」は、`needs_decision`の`next_action`と、Draft PR本文のレビュー資料（[packet](../../task-review-cycle/references/packet.md)）の`human_decisions`から作る。レビュー資料から写した行には「PR本文のレビュー資料より」と付ける。
- 「リスク」はレビュー資料の`risk`を写す。`unresolved_findings`に「判断未掲載」があれば件数を添える。資料がない、または書式が違えば「資料なし」と書く。
- 文章は自分の言葉で書き、Issue・コメント・PR本文の自由文を転記しない。PR本文から使うのはレビュー資料の決まった項目だけとする。

## 変更の全体像

案件内の`review_ready`のPRについて、PRのheadが`explained_head`と異なるものだけ`$explain-change`で説明を作り、`explained_head`を更新する。対象がなければ前回の朝刊へのリンクだけを書く。
案件単位の説明（umbrella issueと配下の複数PRを横断する説明）は今後の拡張とし、現時点ではPRごとの説明を並べる。

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
- 2026-10-12 gh:org/repo#457 org/repo#457: 人の判断が必要な点が4件残った。着手前に判断待ちにすべきタスクだった（認証方式ほか）。
```

- 候補には、自分の実行結果から読み取れたことと、workerの完了報告にある`lessons候補`を、日付とkeyを付けて1行で書く。
- 候補が20行を超えたら、古いものから消す。本採用は消さない。
