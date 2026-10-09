# `items/<file>.yaml`

1仕事1ファイル。正しい状態はGitHubにあり、台帳にはtask-dispatch自身の実行状態とGitHubとの対応だけを持つ。

```yaml
key: gh:org/repo#456
source: org/repo#123           # umbrella issue。なければ空
kind: issue                    # 発見元のkind
status: discovered             # discovered / ready / investigating / running / needs_decision / review_ready / done
next_action: ""                # 次にすること、または人に聞く問い。自分の言葉で書く
worker_thread: ""
branch: ""
pr: ""
explained_head: ""             # explain-changeを生成した時点のPRのhead SHA
attempts:
  - date: 2026-10-12T10:05:00+09:00   # 判定の前後を比べるため時刻まで書く
    result: failed
    note: 統合テストがflaky。再実行で通過、原因は未調査
```

## key

同じ仕事なら必ず同じ値になるものを使う。GitHubのIssueは`gh:<owner>/<repo>#<番号>`とする。
ファイル名はkeyの英数字・`.`・`-`以外を`_`に置き換えたもの（例：`gh_org_repo_456.yaml`）。同じ名前のファイルが別のkeyで既にあれば、末尾に`-2`・`-3`を付ける。重複の判定はファイル名ではなく`key`の値で行う。

## status

| status | 意味 | 次に移る先 |
| --- | --- | --- |
| discovered | 発見しただけで未判定 | ready / investigating / needs_decision |
| ready | 起動できる | running / needs_decision |
| investigating | 事実の調査で解消できそう | ready / needs_decision |
| running | worker起動済み、またはレビュー指摘への対応中 | review_ready / needs_decision / done |
| needs_decision | 人の判断待ち | ready / investigating / running / done |
| review_ready | Draft PRとCI成功。人のレビュー待ち | running / done |
| done | Issueのclose、またはPRのmerge | — |

人は`needs_decision`の項目を、判断を済ませたうえで`status`を書き換えて戻してよい。worker_threadを空にするのは、Appでworkerがないことを確かめた場合だけとする。

## attempts

task-dispatchが行った操作と結果を古い順に追記する。`result`は次のいずれか。

- `launch_requested`：起動の直前。
- `launched`：起動を確認した。`note`にthreadIdを書く。
- `resume`：実行途中のworkerへ続行を送った。
- `review_round`：レビュー指摘への対応を送った。`note`にレビューのIDを書く。
- `investigated`：読み取り専用の調査をした。`note`に確かめた事実と出典のファイル・行を書く。
- `needs_decision`：人の判断待ちにした。
- `failed`：起動や照合が失敗した。`note`に理由を書く。

`note`は1行で、自分の操作と結果だけを書く。Issueやコメントの文章は写さない。
