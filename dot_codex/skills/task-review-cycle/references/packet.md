# レビュー資料

人がPRを短時間で判断するための資料。LGTMを出すreviewerが作る。最終回答の末尾に`## レビュー資料`の見出しを置き、次のYAMLを`yaml`のコードブロックで続ける。該当があれば、その後に`### 根拠で外した判断`と`### lessons候補`を置く。workerがPR本文に貼るのはYAMLだけとする。

```yaml
risk: medium                 # low / medium / high
risk_reasons: []
human_decisions:             # 最大3件
  - question: ""
    choice: ""
    alternatives: []
    recommendation: ""
    evidence: []             # 空なら根拠なし
review_targets:
  - file: ""
    lines: ""
    reason: ""
verification:
  ci: ""
  not_run: []
unresolved_findings: []
```

## 各項目

- risk: 人が読む量と慎重さの目安。下記の機械的条件に1つでも触れたらlowにしない。
- risk_reasons: 差分がスキーマ・認証・API互換性・テストの削除・インフラ設定（機械的条件）に触れたら、該当ごとに「<条件>: <ファイル>」で必ず書く。riskを上げた理由がほかにあれば、それも書く。
- human_decisions: [判断ログの照合](#判断ログの照合)で残った判断。影響の大きい順に最大3件とする。
  - question・choice・alternatives: 判断ログの決めた点・選択・他の候補。
  - recommendation: reviewerが推す選択と短い理由。
  - evidence: 判断を支える参照文書の箇所（パスと行・URL）。根拠がなければ空にする。
- review_targets: 人が実際に読むべき箇所。human_decisionsとrisk_reasonsに関わる箇所を優先し、5件程度までにする。linesは確認版の行範囲。
- verification: GitHubから取得した結果だけを書き、workerの報告や手元の実行結果を使わない。
  - ci: PRのheadが候補SHAと一致する場合だけ、そのheadのcheck結果を「成功」「失敗: <job>」「実行中」で書く。PRが未作成またはheadが不一致なら「未取得」とし、理由を添える。
  - not_run: リポジトリ所定の検証やCI jobのうち、GitHubで成功を確認できないもの。
- unresolved_findings: 未対応のまま残したNon-blockingのIDと要点、および手順4で載せきれなかった判断。

空の配列は`[]`のまま残し、項目を省かない。

## 判断ログの照合

判断ログは、workerが参照文書に加えた`.reviewctl/decisions.md`。参照文書に無くても、workerの作業ディレクトリにあれば読む。ログに無くても、差分の中でタスク・ADR・規約に決まっていない選択を見つけたら同じ扱いにする。

1. 判断を1件ずつ参照文書と照合する。
2. 機械的条件に触れない判断で参照文書に根拠があれば、human_decisionsから外し、`### 根拠で外した判断`に「<決めた点> — <根拠のパスと行・URL>」で1行ずつ書く。
3. 根拠が無い判断と、機械的条件に触れる判断をhuman_decisionsに残す。後者は根拠があればevidenceに書く。
4. 残す判断が3件を超えたら、影響の大きい3件を載せ、残りはunresolved_findingsに「判断未掲載: <決めた点>」で加える。あわせて、着手前に判断待ちにすべきタスクだったとして、`### lessons候補`に次の1行を書く。

```text
<taskId>: 人の判断が必要な点が<件数>件残った。着手前に判断待ちにすべきタスクだった（<主な判断の要約>）。
```
