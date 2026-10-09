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
  - date: 2026-10-12T10:05:00+09:00   # 前後を比べるため時刻まで書く
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
| running | worker起動済み | review_ready / needs_decision / done |
| needs_decision | 人の判断待ち | ready / investigating / running / done |
| review_ready | Draft PRとCI成功。人のレビュー待ち | running / needs_decision / done |
| done | Issueのclose、またはPRのmerge | — |

人は判断を済ませたうえで、`needs_decision`の`status`を書き換えて戻してよい。`worker_thread`に値がある項目は、Appでworkerに続行を指示してから`running`に戻す。`worker_thread`を空にするのは、Appでworkerがないことを確かめた場合だけとする。

## 照合

- Issueがclose、またはPRがmergeされた：`done`。
- PRがmergeされずにcloseされた：`needs_decision`。
- `running`で`worker_thread`が空：`harnexus-task state --request requests/<file>.json`を見る。`workerThreadId`があれば書いて`launched`を追記する。`pending`があれば`needs_decision`にし、Appで確認する内容を`next_action`に書く。どちらもなければ`ready`に戻す。
- `running`で`pr`が空：Issueに紐づくPR（Developmentのリンク、本文で閉じるIssueに指定したPR）を探し、`pr`・`branch`に書く。
- `running`でDraft PRがある：headのCIが成功していれば`review_ready`にする。CIのcheckが1つもなければ成功とみなし、朝刊のリスク欄に「CIなし」と添える。`review_ready`にしたら、`worker_thread`の最新1turnを出力なしで`read_thread`し、完了報告の`lessons候補`を取る。
- `running`でそれ以外：`worker_thread`の最新1turnを出力なしで`read_thread`する。turnが進行中なら何もしない。最終回答で止まっていれば、人の判断を求めている場合は`needs_decision`、それ以外（CIの失敗、手順の途中）は朝刊の「続行が必要」に載せる。idleだけで停止と判断しない。
- `running`で、最後の`launched`から`limits.task_hours`を過ぎた：`needs_decision`にし、止まった位置を`next_action`に書く。
- `review_ready`でPRがReadyになった：人に渡ったものとして`review_ready`のまま残し、未レビューのDraft PRには数えない。
- `review_ready`で、`owner`のレビュー（状態は問わない）またはレビューコメントがあり、そのIDが`attempts`の`review_round`にない：IDを`review_round`で記録し、朝刊の「続行が必要」に載せる。`review_round`が`limits.max_review_rounds`を超えたら`needs_decision`にする。

## attempts

task-dispatchが行った操作と結果を古い順に追記する。`result`は次のいずれか。

- `launch_requested`：起動の直前。
- `launched`：起動を確認した。`note`にthreadIdを書く。
- `review_round`：`owner`のレビューを検出した。`note`にレビューまたはコメントのIDを書く。
- `investigated`：読み取り専用の調査をした。`note`は確かめた点とその真偽、出典のファイル・行だけを書き、コードやコメントを引用しない。
- `needs_decision`：人の判断待ちにした。
- `failed`：起動や照合が失敗した。`note`に理由を書く。

`note`は1行で、自分の操作と結果だけを書く。Issueやコメントの文章は写さない。
