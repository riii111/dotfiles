# `items/<file>.yaml`

1仕事1ファイル。
正しい状態はGitHubにあり、台帳にはtask-dispatch自身の実行状態とGitHubとの対応だけを持つ。
人は台帳を編集しない。

```yaml
key: gh:org/repo#456
source: org/repo#123           # umbrella issue。なければ空
kind: issue                    # 発見元のkind（issue / improvement）
status: discovered             # discovered / ready / running / needs_decision / review_ready / done
next_action: ""                # 次にすること、または止まった位置。自分の言葉で書く
question: ""                   # 予定で聞く問い。選択肢と推奨を付け、答えで判定し直したら空にする
worker_thread: ""
branch: ""
pr: ""
attempts:
  - date: 2026-10-12T10:05:00+09:00   # 前後を比べるため時刻まで書く
    result: failed
    note: 統合テストがflaky。再実行で通過、原因は未調査
```

## key

同じ仕事なら必ず同じ値になるものを使う。
GitHubのIssueは`gh:<owner>/<repo>#<番号>`とする。
ファイル名はkeyの英数字・`.`・`-`以外を`_`に置き換えたもの（例：`gh_org_repo_456.yaml`）。
重複の判定はファイル名ではなく`key`の値で行う。

## status

| status | 意味 |
| --- | --- |
| discovered | 発見しただけで未判定 |
| ready | 起動できる |
| running | worker起動済みで、現在のheadはまだレビュー可能でない |
| needs_decision | 人の判断待ち |
| review_ready | 現在のheadがレビュー可能。人のレビュー待ち |
| done | Issueのclose、またはPRのmerge |

`status`を変えるのは、この節の遷移表・[起動](launch.md)・[続行の送信](continue.md)・[報告のスレッドへの返事](schedule.md#報告のスレッドへの返事)だけとする。
人の判断を求めて止まったworkerには、人がAppでworkerに直接答えるか、IssueかPRへのコメントか予定のスレッドで答える。
`worker_thread`を空にするのは、ユーザーがスレッドでworkerがないと伝えた場合だけとする。

### レビュー可能

照合のたびに、PRの現在のheadについて次をすべて確かめる。前回の結果は引き継がない。

- PRがopenである。
- 現在のheadのcheckがすべて成功している。
  `config.yaml`の`repos`で`ci: false`としたリポジトリだけはcheckなしでよい。
  checkが1つもなければ、まだ登録されていないものとして満たさない。
- `worker_thread`の最新turnが、独立レビューのLGTMとCIの成功を伝える完了報告で終わっている。
  完了報告に人の判断が必要な点や確かめていないことがあっても、ここでは満たすものとし、朝の報告で伝える。
- `harnexus-task state --request <作業ディレクトリ>/.reviewctl/request.json`の`head`（最後に独立レビューへ送ったhead）が現在のheadと一致する。
  作業ディレクトリは、`config.yaml`の`repos.<owner/repo>.path`で`git worktree list --porcelain`を実行し、itemの`branch`と一致するものとする。見つからなければ満たさない。

### 遷移表

照合で使う。
上の行から順に当てはめ、最初に当たった行だけを使う。
`done`の項目は照合しない。
表を当てはめる前に、`pr`が空の`running`は、Issueに紐づくPR（Developmentのリンク、本文で閉じるIssueに指定したPR）を探し、あれば`pr`・`branch`に書く。PRがなければレビュー可能ではない。

| 現在 | 条件 | 移る先 | 記録 |
| --- | --- | --- | --- |
| すべて | Issueがclose、またはPRがmergeされた | done | `status` |
| running・review_ready | PRがmergeされずにcloseされた | needs_decision | `status` |
| running | `worker_thread`が空 | 下記「起動結果の確認」 | 下記 |
| running | レビュー可能 | review_ready | `status`（noteにhead） |
| running | worker_threadの最新turnが、大きな設計判断を求める最終回答で止まっている | needs_decision（問いを`question`に書く） | `status` |
| running | worker_threadの最新turnが、それ以外の最終回答で止まっている | [続行の送信](continue.md)の理由`stopped`として起動の回で決める | なし |
| running | 上のどれでもない（turnが進行中、CIが実行中など） | running | なし |
| review_ready | 現在のheadでレビュー可能でない | running | `status`（noteに理由：headの更新・CI実行中・CI失敗・レビュー未了） |
| review_ready | 上のどれでもない | review_ready（続行の理由があれば起動の回で[続行の送信](continue.md)を決める） | なし |
| needs_decision | `worker_thread`の最新turnが、最後に`needs_decision`へ移した後に始まっている（人がAppで答えて再開した） | running | `status` |
| discovered | [着手できるか判断する](plan.md#着手できるか判断する) | ready・needs_decision | `status` |
| needs_decision | [着手できるか判断する](plan.md#着手できるか判断する)の再判定条件を満たした | ready・needs_decision | `status` |

`running`のturnは、`worker_thread`の最新1turnを出力なしで`read_thread`して確かめる。idleだけで停止と判断しない。
`ready`から先の遷移（起動、確認を通らない場合、起動の失敗）は照合ではなく[起動](launch.md)の手順で決め、この表は使わない。
判定の2行（`discovered`と判定による`needs_decision`）は予定の回だけで使い、ほかの回では状態を変えない。

headが更新されたときの例：

| 段階 | 照合の結果 |
| --- | --- |
| headのCIが成功し、そのheadで独立レビューを終えてworkerが完了を報告した | running → review_ready |
| ownerのレビューを受けてworkerが修正をpush | review_ready → running（headの更新・CI実行中） |
| 新しいheadのCIが失敗し、workerが止まった | runningのまま。次の起動の回で続行を送る |
| 新しいheadのCIが成功したが、独立レビューはまだ古いhead | runningのまま（レビュー未了） |
| 新しいheadで独立レビューを終え、workerが完了を報告した | running → review_ready |

### 起動結果の確認

`running`で`worker_thread`が空なら、起動結果を記録する前に止まった項目として`harnexus-task state --request requests/<file>.json`を見る。
`workerThreadId`があれば書いて`launched`を追記する。
`pending`があれば`needs_decision`にし、Appで確認する内容を`next_action`に書く。どちらもなければ`ready`に戻す。
状態を変えたら`status`を記録する。

## ownerのレビュー

`owner`のpull request review（`COMMENTED`または`CHANGES_REQUESTED`）のうち、レビューのcommitがPRの現在のheadと同じものを未対応とする。
未対応のレビューへの対応は[続行の送信](continue.md)で送る。
workerが修正をpushしてheadが変われば、そのレビューは対応済みになる。

## attempts

task-dispatchが行った操作と結果を古い順に追記する。
`note`は1行で、自分の操作と結果だけを書く。Issueやコメントの文章は写さない。

| result | 書くとき | note |
| --- | --- | --- |
| `status` | `status`を変えた | 「<前>→<後>: <理由>」 |
| `planned` | 予定か追加分に新規起動として載せた | `launch`。追加分は`launch 追加分`、答えで起動するものは`launch 答え` |
| `plan_cancelled` | `planned`を起動せずに閉じた | 理由（返事で取り消し・再計画・持ち越し・予定から変わった点） |
| `approved` | ownerのOKを受けた | なし。[返事がなかった日](launch.md#返事がなかった日)は`返事なし`、答えで起動するものは`答え` |
| `approval_revoked` | OKを取り消した | 理由（返事で取り消し） |
| `launch_requested` | 起動の直前。`ready`→`running`の記録を兼ねる | なし |
| `launched` | 起動を確認した | threadId |
| `continue_sent` | workerへ続行を送った | 「<理由> head=<先頭7桁> ref=<ref>」。headはPRの現在のhead、PRがなければ`-` |
| `failed` | 起動・照合・送信が失敗した | 理由 |

`planned`の後に`launch_requested`・`plan_cancelled`・`failed`のどれもなければ、まだ使われていない。
