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
handled_reviews: []            # 人が書く。push以外で対応を済ませたownerのレビューID
attempts:
  - date: 2026-10-12T10:05:00+09:00   # 前後を比べるため時刻まで書く
    result: failed
    note: 統合テストがflaky。再実行で通過、原因は未調査
```

## key

同じ仕事なら必ず同じ値になるものを使う。GitHubのIssueは`gh:<owner>/<repo>#<番号>`とする。
ファイル名はkeyの英数字・`.`・`-`以外を`_`に置き換えたもの（例：`gh_org_repo_456.yaml`）。同じ名前のファイルが別のkeyで既にあれば、末尾に`-2`・`-3`を付ける。重複の判定はファイル名ではなく`key`の値で行う。

## status

| status | 意味 |
| --- | --- |
| discovered | 発見しただけで未判定 |
| ready | 起動できる |
| investigating | 事実の調査で解消できそう |
| running | worker起動済みで、現在のheadはまだレビュー可能でない |
| needs_decision | 人の判断待ち |
| review_ready | 現在のheadがレビュー可能。人のレビュー待ち |
| done | Issueのclose、またはPRのmerge |

`status`を変えるのはこの節の遷移表だけとする。人は判断を済ませたうえで、`needs_decision`の`status`を書き換えて戻してよい。`worker_thread`に値がある項目は、Appでworkerに続行を指示してから`running`に戻す。`worker_thread`を空にするのは、Appでworkerがないことを確かめた場合だけとする。

### レビュー可能

照合のたびに、PRの現在のheadについて次をすべて確かめる。前回の結果は引き継がない。

- PRがopenである。
- 現在のheadのcheckがすべて成功している。`config.yaml`の`repos`で`ci: false`としたリポジトリだけはcheckなしでよい。checkが1つもなければ、まだ登録されていないものとして満たさない。
- PR本文の[レビュー資料](../../task-review-cycle/references/packet.md)の`head`が現在のheadと一致する。資料がない、または書式が違う場合は満たすものとし、朝刊で「資料なし」と示す。

### 遷移表

照合で使う。上の行から順に当てはめ、最初に当たった行だけを使う。`done`の項目は照合しない。
表を当てはめる前に、次の2つを済ませる。

- 人による変更の検出：itemの`status`が、`attempts`の最後の`status`記録の移った先（それより新しい`launch_requested`があれば`running`）と違えば、人が書き換えたものとして`status`を「<前>→<後>: 人が変更」で記録する。
- `pr`が空の`running`は、Issueに紐づくPR（Developmentのリンク、本文で閉じるIssueに指定したPR）を探し、あれば`pr`・`branch`に書く。PRがなければレビュー可能ではない。

| 現在 | 条件 | 移る先 | 記録 |
| --- | --- | --- | --- |
| すべて | Issueがclose、またはPRがmergeされた | done | `status` |
| running・review_ready | PRがmergeされずにcloseされた | needs_decision | `status` |
| running | `worker_thread`が空 | 下記「起動結果の確認」 | 下記 |
| running | レビュー可能 | review_ready | `status`（noteにhead） |
| running | worker_threadの最新turnが、人の判断を求める最終回答で止まっている | needs_decision | `status` |
| running | worker_threadの最新turnが、それ以外の最終回答で止まっている | running（朝刊の「続行が必要」） | 最後の`running`以降で初回だけ`continue_listed` |
| running | 最後に`running`へ移してから`limits.task_hours`を過ぎ、その後に`continue_listed`がない | needs_decision（止まった位置を`next_action`に書く） | `status` |
| running | 上のどれでもない（turnが進行中、CIが実行中など） | running | なし |
| review_ready | 現在のheadでレビュー可能でない | running | `status`（noteに理由：headの更新・CI実行中・CI失敗・資料が古い） |
| review_ready | 新しい`owner`のレビューで`review_round`が`limits.max_review_rounds`を超えた | needs_decision | `review_round`・`status` |
| review_ready | `review_round`にない`owner`のレビューがある | review_ready | `review_round` |
| review_ready | 上のどれでもない | review_ready | なし |
| discovered・investigating | SKILLの判定 | ready・investigating・needs_decision | `status` |
| needs_decision | SKILLの判定で再判定の条件を満たした | ready・investigating・needs_decision | `status` |

`running`のturnは、`worker_thread`の最新1turnを出力なしで`read_thread`して確かめる。idleだけで停止と判断しない。
「最後に`running`へ移した」時刻は、最後の`launched`または`→running`の`status`のうち新しいほうとする。人が`running`へ戻した場合も、検出時の記録から数え直す。
`ready`から先の遷移（起動、確認を通らない場合、起動の失敗）は照合ではなく[起動](launch.md)の手順で決め、この表は使わない。

headが更新されたときの例：

| 段階 | 照合の結果 |
| --- | --- |
| headのCIが成功し、資料のheadも一致 | running → review_ready |
| ownerのレビューを受けてworkerが修正をpush | review_ready → running（headの更新・CI実行中） |
| 新しいheadのCIが失敗し、workerが止まった | runningのまま。朝刊の「続行が必要」に載せる |
| 新しいheadのCIが成功したが、資料はまだ古いhead | runningのまま。朝刊で「資料が古い」と示す |
| 新しいheadのCIが成功し、資料も差し替わった | running → review_ready |

### 起動結果の確認

`running`で`worker_thread`が空なら、起動結果を記録する前に止まった項目として`harnexus-task state --request requests/<file>.json`を見る。`workerThreadId`があれば書いて`launched`を追記する。`pending`があれば`needs_decision`にし、Appで確認する内容を`next_action`に書く。どちらもなければ`ready`に戻す。状態を変えたら`status`を記録する。

## ownerのレビュー

`owner`のpull request review（`COMMENTED`または`CHANGES_REQUESTED`）を、次の2つに分けて扱う。

- 往復の回数：レビューのIDが`attempts`の`review_round`になければ、IDを`review_round`で記録する。回数は`review_round`の件数で数え、同じレビューを二度数えない。レビューに属するコメントは別に数えない。
- 未対応の続行依頼：レビューのcommitがPRの現在のheadと同じで、そのIDが`handled_reviews`にないものは未対応とする。未対応のレビューがある項目は、照合のたびに朝刊の「続行が必要」に載せる。記録の有無や前回の掲載では外さない。

workerが修正をpushしてheadが変われば、そのレビューは対応済みになる。pushを伴わない対応で済んだ場合は、人がそのIDを`handled_reviews`に書く。

## 問いへの回答

`head`が現在のheadと一致するレビュー資料の`human_decisions`について、その資料のheadのcommit以降に`owner`が書いたPRのコメントとレビューを読み、各問いに答えているかを確かめる。答えていれば`decision_answered`を記録し、同じheadの間は朝刊の問いに載せない。答えが変更を求める場合は、workerへの指示が要るため「続行が必要」に載せる。
答えたかどうか判断できない問いは載せたままにする。`owner`以外の書き込みは回答として扱わない。

## lessonsの読み取り

`review_ready`で、現在のheadについての`lessons_read`がなければ、`worker_thread`の最新1turnを出力なしで`read_thread`する。turnが終わっていれば完了報告の`lessons候補`を取り、`lessons_read`をhead付きで追記する。進行中なら次回に持ち越す。

## attempts

task-dispatchが行った操作と結果を古い順に追記する。`result`は次のいずれか。

- `status`：`status`を変えた。`note`に「<前>→<後>: <理由>」を書く。
- `launch_requested`：起動の直前。`ready`→`running`の記録を兼ねる。
- `launched`：起動を確認した。`note`にthreadIdを書く。
- `review_round`：`owner`のレビューを検出した。`note`にレビューのIDを書く。
- `continue_listed`：`running`の項目を朝刊の「続行が必要」に初めて載せた。
- `decision_answered`：レビュー資料の問いに`owner`が答えていた。`note`にheadの先頭7桁と問いの要約を自分の言葉で書く。
- `lessons_read`：workerの完了報告から`lessons候補`を読んだ。`note`にheadを書く。
- `investigated`：読み取り専用の調査をした。`note`は確かめた点とその真偽、出典のファイル・行だけを書き、コードやコメントを引用しない。
- `failed`：起動や照合が失敗した。`note`に理由を書く。

`note`は1行で、自分の操作と結果だけを書く。Issueやコメントの文章は写さない。
