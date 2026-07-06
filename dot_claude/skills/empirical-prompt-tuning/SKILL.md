---
name: empirical-prompt-tuning
description: |
  ユーザーが empirical prompt tuning、prompt evaluation、subagent を使った prompt / skill tuning を明示した場合だけ使う。通常のprompt修正、code review、文章の好み調整では発火しない。固定シナリオをfresh subagentに実行させ、事前定義したchecklistで評価し、観測された曖昧さに基づいてprompt/skillを小さく直す。
---

# empirical-prompt-tuning

prompt / skill を自己再読ではなく、実行結果から調整する。

## 使う条件

ユーザーがこの手法、empirical prompt tuning、subagent評価、prompt/skillの実証的改善を明示したときだけ使う。

一回限りの文章作成、通常のcode review、主観的な言い換えには使わない。

## Workflow

1. 静的チェック
   - 対象prompt/skillのdescriptionと本文を読む。
   - trigger / 用途説明と、本文の手順が噛み合っているか確認する。
   - 明らかな乖離があれば、empirical実行前に直す。

2. baseline準備
   - 現実的なシナリオを2-3個用意する。中央値1つ、edge 1-2個。
   - 各シナリオに3-7個のchecklistを事前に書く。
   - 最低1項目は `[critical]` にする。
   - 結果を見た後でchecklistを変えない。

3. fresh subagent実行
   - シナリオごとに新しいsubagentを起動する。
   - 対象prompt/skill、シナリオ、checklist、report formatを渡す。
   - 意図した修正案や仮説は、検証対象でない限り渡さない。

4. 両面評価
   - subagent自己申告から、不明瞭点・裁量補完・再試行を集める。
   - 成果物から、checklistを `○` / `×` / `partial` で採点する。
   - `[critical]` が全て `○` の場合だけ成功とする。
   - 定性的な曖昧さを主信号にする。時間やtool countは補助扱いにする。

5. 1テーマだけ直す
   - 新しく出た曖昧さを潰す最小修正を入れる。
   - 編集前に、どのchecklist項目を改善する修正かを明示する。
   - 無関係な改善は次のiterationに回す。

6. fresh subagentで再実行
   - 同じsubagentを再利用しない。
   - 新しい曖昧さが2iteration連続で出ない、または改善コストが見合わなくなったら止める。

## Subagent prompt template

```markdown
あなたは <target prompt/skill> を白紙で読む実行者です。

## Target prompt
<全文、または読むべきpath>

## Scenario
<現実的なタスク設定>

## Requirement checklist
1. [critical] <must-pass requirement>
2. <requirement>
3. <requirement>

## Task
対象promptに従ってscenarioを実行し、期待される成果物を生成してください。
その後、次の形式で報告してください。
- 成果物
- 要件達成: 各checklist項目を ○ / × / partial と理由で評価
- 不明瞭点
- 裁量補完
- 再試行
```

## Reporting

iterationごとに次をまとめる:
- 変更したprompt/skill箇所
- scenarioごとの結果とchecklist score
- 新しく出た不明瞭点
- subagentが裁量で補ったこと
- 次の最小修正

最終提案とsubagentの生メモは分ける。
