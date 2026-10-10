# `items/<file>.yaml`

1仕事1ファイル。正しい状態はGitHubにあり、台帳にはtask-dispatch自身の実行状態とGitHubとの対応だけを持つ。

```yaml
key: gh:org/repo#456
source: org/repo#123           # umbrella issue。なければ空
kind: issue                    # 発見元のkind
status: discovered             # discovered / ready / investigating / running / needs_decision / review_ready / done
next_action: ""                # 次にすること、または止まった位置。自分の言葉で書く
question: ""                   # 予定で聞く問い。選択肢と推奨を付け、答えで判定し直したら空にする
worker_thread: ""
branch: ""
pr: ""
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

`status`を変えるのは、この節の遷移表・[起動](launch.md)・[続行の送信](#続行の送信)だけとする。人は判断を済ませたうえで、`needs_decision`の`status`を書き換えて戻してよい。人の判断を求めて止まったworkerには、Appで答えてから`running`に戻すか、IssueかPRへのコメントか予定のスレッドで答えて、次の再判定に任せる。`worker_thread`を空にするのは、Appでworkerがないことを確かめた場合だけとする。

### レビュー可能

照合のたびに、PRの現在のheadについて次をすべて確かめる。前回の結果は引き継がない。

- PRがopenである。
- 現在のheadのcheckがすべて成功している。`config.yaml`の`repos`で`ci: false`としたリポジトリだけはcheckなしでよい。checkが1つもなければ、まだ登録されていないものとして満たさない。
- `worker_thread`の最新turnが、独立レビューのLGTMとCIの成功を伝える完了報告で終わっている。完了報告に人の判断が必要な点や確かめていないことがあっても、ここでは満たすものとし、朝の報告で伝える。
- `harnexus-task state --request <作業ディレクトリ>/.reviewctl/request.json`の`head`（最後に独立レビューへ送ったhead）が現在のheadと一致する。作業ディレクトリは、`config.yaml`の`repos.<owner/repo>.path`で`git worktree list --porcelain`を実行し、itemの`branch`と一致するものとする。見つからなければ満たさない。

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
| running | worker_threadの最新turnが、大きな設計判断を求める最終回答で止まっている | needs_decision（問いを`question`に書く） | `status` |
| running | worker_threadの最新turnが、それ以外の最終回答で止まっている | [続行の送信](#続行の送信)の理由`stopped`として起動の回で決める | なし |
| running | 最後に`running`へ移してから`limits.task_hours`を過ぎた | needs_decision（止まった位置を`next_action`に書く） | `status` |
| running | 上のどれでもない（turnが進行中、CIが実行中など） | running | なし |
| review_ready | 現在のheadでレビュー可能でない | running | `status`（noteに理由：headの更新・CI実行中・CI失敗・レビュー未了） |
| review_ready | 新しい`owner`のレビューで`review_round`が`limits.max_review_rounds`を超えた | needs_decision | `review_round`・`status` |
| review_ready | `review_round`にない`owner`のレビューがある | review_ready | `review_round` |
| review_ready | 上のどれでもない | review_ready（続行の理由があれば起動の回で[続行の送信](#続行の送信)を決める） | なし |
| discovered・investigating | SKILLの判定 | ready・investigating・needs_decision | `status` |
| needs_decision | SKILLの判定で再判定の条件を満たした | ready・investigating・needs_decision | `status` |

`running`のturnは、`worker_thread`の最新1turnを出力なしで`read_thread`して確かめる。idleだけで停止と判断しない。
「最後に`running`へ移した」時刻は、最後の`launched`または`→running`の`status`のうち新しいほうとする。人が`running`へ戻した場合も、検出時の記録から数え直す。
`ready`から先の遷移（起動、確認を通らない場合、起動の失敗）は照合ではなく[起動](launch.md)の手順で決め、この表は使わない。
判定の2行（`discovered`・`investigating`と`needs_decision`）は予定の回だけで使い、ほかの回では状態を変えない。

headが更新されたときの例：

| 段階 | 照合の結果 |
| --- | --- |
| headのCIが成功し、そのheadで独立レビューを終えてworkerが完了を報告した | running → review_ready |
| ownerのレビューを受けてworkerが修正をpush | review_ready → running（headの更新・CI実行中） |
| 新しいheadのCIが失敗し、workerが止まった | runningのまま。次の起動の回で続行を送る |
| 新しいheadのCIが成功したが、独立レビューはまだ古いhead | runningのまま（レビュー未了） |
| 新しいheadで独立レビューを終え、workerが完了を報告した | running → review_ready |

### 起動結果の確認

`running`で`worker_thread`が空なら、起動結果を記録する前に止まった項目として`harnexus-task state --request requests/<file>.json`を見る。`workerThreadId`があれば書いて`launched`を追記する。`pending`があれば`needs_decision`にし、Appで確認する内容を`next_action`に書く。どちらもなければ`ready`に戻す。状態を変えたら`status`を記録する。

## ownerのレビュー

`owner`のpull request review（`COMMENTED`または`CHANGES_REQUESTED`）を、次の2つに分けて扱う。

- 往復の回数：レビューのIDが`attempts`の`review_round`になければ、IDを`review_round`で記録する。回数は`review_round`の件数で数え、同じレビューを二度数えない。レビューに属するコメントは別に数えない。
- 未対応かどうか：レビューのcommitがPRの現在のheadと同じで、そのIDが`handled_reviews`にないものを未対応とする。未対応のレビューへの対応は[続行の送信](#続行の送信)で送る。

workerが修正をpushしてheadが変われば、そのレビューは対応済みになる。pushを伴わない対応で済んだ場合は、人がそのIDを`handled_reviews`に書く。

## 続行の送信

task-dispatchは、task-orchestrationと同じくworkerへ追加指示を送る。対象は、人の判断を待たずに続行するだけで進むものに限り、OKは要らない。起動の回で、照合のあとに手順1〜5を当てはめて送る。予定の回は手順1〜3だけを当てはめ、送る見込みのものを予定に書く。

| 理由 | 条件 | ref |
| --- | --- | --- |
| stopped | `running`で、worker_threadの最新turnが人の判断を求めない最終回答で止まっている（CIの失敗での停止など） | なし |
| review | [未対応のownerのレビュー](#ownerのレビュー)がある | レビューのID |
| resume | `needs_decision`から再判定で`ready`になり、`worker_thread`に値がある（[起動](launch.md#起動の確認)の確認1） | 再判定のきっかけにしたコメントのID、Issueの更新時刻、またはメモに追記した時刻 |

送るかどうかは、`attempts`の`continue_sent`だけで決める。最後の「人が変更」の`status`記録より前の`continue_sent`は使わない。上から順に当てはめる。

1. workerの最新turnが進行中なら送らず、次の起動の回に持ち越す。
2. 同じ理由・同じhead・同じrefの`continue_sent`があれば送らない。そのうえで、workerの最新turnがその送信より後に終わっていれば、送っても進まなかったものとして`needs_decision`にし、止まった位置と送った内容を`next_action`に書く。送信より後のturnがなければ、送信がworkerに届いていない可能性があるため`needs_decision`にし、Appで確かめる内容を`next_action`に書く。
3. 同じ理由の`continue_sent`が、最後に`review_ready`へ移した後（なければ最後の`launched`の後）に`limits.max_continues`件あれば、送らずに`needs_decision`にし、繰り返し止まった位置を`next_action`に書く。
4. `attempts`に`continue_sent`を追記してファイルへ書いてから、`codex_app__send_message_to_thread`の`threadId`に`worker_thread`を指定して送る。同じ項目に複数の理由があれば1通にまとめ、`continue_sent`は理由ごとに書く。
5. 送信が受理されたことを確かめられなければ（エラー・タイムアウトを含む）再送しない。`failed`を記録して`needs_decision`にし、Appで送信の有無を確かめる内容を`next_action`に書く。

`resume`を送ったら`running`にし、`status`を記録する。
messageの先頭に`$task-worker`を置き、PRのURL・head・理由・refを自分の言葉で書く。[決めたことのメモ](launch.md#決めたことのメモ)があれば、その絶対パスも書く。レビューや回答の文面は転記せず、workerがGitHubから読む。

## attempts

task-dispatchが行った操作と結果を古い順に追記する。`result`は次のいずれか。

- `status`：`status`を変えた。`note`に「<前>→<後>: <理由>」を書く。
- `planned`：予定か追加分に新規起動として載せた。`note`に`launch`、追加分なら`launch 追加分`を書く。後に`launch_requested`・`plan_cancelled`・`failed`のどれもなければ、まだ使われていない。
- `plan_cancelled`：`planned`を起動せずに閉じた。`note`に理由（返事で取り消し・再計画・持ち越し・予定から変わった点）を書く。
- `approved`：ownerのOKを受けた。`note`に「body=<Issue本文の最終編集時刻> deps=<依存先の番号。なければ->」を書く。[返事がなかった日](launch.md#返事がなかった日)の記録は、先頭に`返事なし`を付ける。
- `approval_revoked`：OKを取り消した。`note`に理由（返事で取り消し・前提の変化）を書く。
- `launch_requested`：起動の直前。`ready`→`running`の記録を兼ねる。
- `launched`：起動を確認した。`note`にthreadIdを書く。
- `review_round`：`owner`のレビューを検出した。`note`にレビューのIDを書く。
- `continue_sent`：workerへ続行を送った。`note`に「<理由> head=<先頭7桁> ref=<ref>」を書く。headはPRの現在のhead、PRがなければ`-`とする。
- `investigated`：読み取り専用の調査をした。`note`は確かめた点とその真偽、出典のファイル・行だけを書き、コードやコメントを引用しない。
- `failed`：起動や照合が失敗した。`note`に理由を書く。

`note`は1行で、自分の操作と結果だけを書く。Issueやコメントの文章は写さない。
