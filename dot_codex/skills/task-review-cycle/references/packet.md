# レビュー資料

人がPRを短時間で判断するための資料。LGTMを出すreviewerが作る。最終回答の末尾に`## レビュー資料`の見出しを置き、次のYAMLを`yaml`のコードブロックで続ける。該当があれば、その後に`### lessons候補`を置く。workerは完了報告にYAMLを含める。資料は人に読ませるものではなく、ディスパッチの朝刊の材料にする。PR本文・PRのコメントなどGitHubには載せない。

```yaml
head: ""                     # 資料の対象のcommit SHA
reading: key_points          # deep / key_points / skim
reading_reason: ""
risk_reasons: []
human_decisions:             # 表示は3件まで
  - question: ""
    where:
      file: ""
      lines: ""
    choice: ""
    alternatives: []
    recommendation: ""
    evidence: []
grounded_decisions:
  - decision: ""
    reason: ""
    evidence: []
review_targets:
  - file: ""
    lines: ""
    reason: ""
verification:
  ci: ""
  ci_url: ""
  unconfirmed: []
unresolved_findings: []
```

## 各項目

- head: LGTMを出した候補SHA（40桁）。資料はこのheadについてだけ有効で、PRのheadと違えば古い資料として扱われる。
- reading: 人がPRをどう読めばよいか。次のうち当てはまる最初のものにする。
  - deep（じっくり）：機械的条件（スキーマ・認証・API互換性・テストの削除・インフラ設定）に1つでも触れる。ほかに全体を読まないと判断できない理由があれば、それも含める。
  - key_points（要点だけ）：挙動や公開されるものが変わるが、review_targetsを読めば判断できる。human_decisionsが残っている場合も、少なくともこれにする。
  - skim（流し読み）：挙動が変わらない（ログ・文言・内部の整理など）。
- reading_reason: readingを選んだ理由を、差分で何が変わるかで1文に書く（例：「決済テーブルにカラムを追加するマイグレーションを含む」）。「影響が大きい」のような評価だけにしない。
- risk_reasons: 差分が機械的条件に触れたら、該当ごとに「<条件>: <ファイル>」で必ず書く。参照文書に根拠がある変更でも省かない。readingを上げた理由がほかにあれば、それも書く。
- human_decisions: [判断ログの照合](#判断ログの照合)で残った、根拠がなく人が答えないと決まらない判断。影響の大きい順に3件まで載せる。
  - question・choice・alternatives: 判断ログの決めた点・選択・他の候補。
  - where: 判断が現れる差分の箇所（ファイルと確認版の行範囲）。人がその行へコメントして答えるために使う。複数あれば代表的な1箇所にし、差分に現れなければ空にする。
  - recommendation: reviewerが推す選択と短い理由。
  - evidence: 判断の材料になる参照文書の箇所（URL、またはリポジトリ内のパスと`head`時点の行）。決め手にならない材料だけなら、それを書く。なければ空にする。判断ログ・worktreeの絶対パス・確かめていないことは書かない。確かめていないことはrecommendationの理由に書く。
- grounded_decisions: 照合で参照文書に根拠が見つかり、human_decisionsから外した判断。人は答えなくてよいが、違うと思えばPRにコメントする。
  - decision: 決めた点と選んだものを1文で書く（例：「バックオフは指数関数で、最大5回にした」）。
  - reason・evidence: 根拠の要点と、参照文書の箇所。evidenceの書き方はhuman_decisionsと同じ。
- review_targets: 人が実際に読むべき箇所。機械的条件に触れる箇所は必ず含め、human_decisionsに関わる箇所を次に優先し、合わせて5件程度までにする。linesは確認版の行範囲。
- verification: GitHubから取得した結果だけを書き、workerの報告や手元の実行結果を使わない。
  - ci: PRのheadが`head`と一致する場合だけ、そのheadのcheck結果を「成功」「失敗: <job>」「実行中」で書く。PRが未作成またはheadが不一致なら「未取得」とし、理由を添える。
  - ci_url: `ci`を取ったheadのcheck一覧のURL。取れなければ空にする。
  - unconfirmed: リポジトリ所定の検証やCI jobのうち、GitHubで成功を確認できないもの。ローカルで実行済みでも、GitHubに結果がなければここに入れる。再検証を求める意味ではなく、人がGitHub上で確かめられないことを示す。
- unresolved_findings: 未対応のまま残したNon-blockingのIDと要点、および照合の手順4で載せきれなかった判断。

空の配列は`[]`のまま残し、項目を省かない。

## 判断ログの照合

判断ログは、workerが参照文書に加えた`.reviewctl/decisions.md`。参照文書に無くても、workerの作業ディレクトリにあれば読む。ログに無くても、差分の中で[task-worker](../../task-worker/SKILL.md#判断ログ)の記録対象に当たる選択を見つけたら同じ扱いにする。

1. 判断を1件ずつ参照文書（タスク・ADR・規約）と照合する。
2. 参照文書に根拠がある判断は、機械的条件に触れていてもhuman_decisionsから外し、grounded_decisionsに書く。機械的条件に触れる箇所は、risk_reasonsとreview_targetsに残す。
3. 根拠が無く、人が答えないと決まらない判断だけをhuman_decisionsに残す。
4. 残した判断が3件を超えたら、影響の大きい3件を載せ、残りはunresolved_findingsに「判断未掲載: <決めた点>」で加える。
5. 残した判断が1件以上あれば、`### lessons候補`に次の1行を書く。件数は載せきれなかった分も含める。

```text
<taskId>: 根拠のない判断が<件数>件残った（<主な判断の要約>）。
```

この行は観測した事実だけを書き、着手前に判断待ちにすべきだったかは書かない。重大な判断は1件でも止めるべき場合があり、実装して初めて分かる論点もあるため、件数だけでは決めない。見直すのは人とする。
