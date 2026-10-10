# 承認と起動

## 1日の段取り

報告の回は、報告を書く前にその日の退勤予定を決めて予定の回を登録する。Calendarを使うかは`config.yaml`の`calendar.enabled`で決める。

1. 前日以前の`days/<日付>.yaml`に残っているScheduled Taskを`automation_update`で消し、予定のスレッドをアーカイブして、どちらも空にする。
2. 使われていない`planned`（追加分を含む）をすべて`plan_cancelled`（note：持ち越し）で閉じる。OKのないまま翌朝になった項目は始めず、次の予定に載せ直す。有効なOKは残るため、次の予定で聞き直さない。
3. 退勤予定を次の順で決める。
   - Calendarがオンなら、Calendarのプラグインで今日の予定を一度だけ読む。終日の不在（outOfOffice）があれば休みとし、`leave_at: off`を書いてここで終える。報告にも書かない。`calendar.leave_title`と同じ名前の予定があればその開始時刻、なければその日の終わりまで続く不在（午後の半休）の開始時刻を退勤予定にする。午前だけの不在は退勤予定にしない。
   - Calendarがオンで決まらなければ、退勤予定を空のままにし、報告のスレッドで退勤時刻を聞く。予定の回は、返事を受けてから登録する。返事がなければ、その日は予定を作らない。
   - Calendarがオフなら、`schedule.plan_at`の1時間後を退勤予定とする。
4. 退勤予定があれば、その1時間前（過ぎていれば10分後）に予定の回を`$task-dispatch 予定`で登録し、時刻を報告の冒頭に書く。
5. `days/<日付>.yaml`を書く。

```yaml
date: 2026-10-14
leave_at: "17:30"     # 退勤予定。休みはoff、返事待ちは空
plan_at: "16:30"      # 予定の回の時刻
plan_task: ""         # 予定の回のScheduled TaskのID
plan_thread: ""       # 予定のスレッドのID
amount: ""            # 量の指定。more・less・数。なければ空
```

予定・起動・返事の回は、`date`が最も新しい`days/<日付>.yaml`を使う。日付をまたいでも、翌朝の報告の回が次の日のファイルを作るまでは同じファイルを使う。

報告のスレッドへの返事では、次だけを行う。

- 退勤時刻：その1時間前（過ぎていれば10分後）に予定の回を登録し、`leave_at`・`plan_at`・`plan_task`を書いて、時刻を返す。予定の回が登録済みなら時刻を動かす。
- 休み：`leave_at: off`を書き、登録済みの予定の回があれば消す。
- 報告の内容への問い：台帳とGitHubから説明する。

### Scheduled Taskの扱い

Scheduled Taskは、Codexスレッドで使える`automation_update`で作成・更新・削除し、`~/agent-desk/`を作業ディレクトリにする。

- 作る前に`plan_task`を見て、IDがあれば作らずに時刻を更新する。作ったらすぐIDを書く。作成の結果が分からなければ作り直さず、`## そのほか`に書き、Appで確かめるよう伝える。
- 予定の回は1回だけ動かす。予定を書き終えたら、`plan_task`を消して空にする。時間を過ぎても、自分のスレッドの記録と`plan_task`の削除は済ませる。lockを取れなかったときは、自分の時刻を10分後へ移して終了する。
- 消せなかったIDは`days/<日付>.yaml`に残し、`## そのほか`に書く。次の朝の段取りで消す。

### スレッドの扱い

予定のスレッドは、自分のスレッドのID（`CODEX_THREAD_ID`）を`plan_thread`に書き、ユーザーの返事を待つ。
返事の回のたびに、その予定と追加分の新規起動の`planned`がすべて決着したかを確かめ、決着していれば最後の返事を返してから自分をアーカイブし、`plan_thread`を空にする。決着とは、起動した・取り消した・外れた（`plan_cancelled`）のどれかになったことをいう。新規起動を1件も載せなかった予定は、予定を書き終えた時点でアーカイブせず、翌朝の段取りでアーカイブする。

## 承認

### OKの受け取り方

返事は自由な文で受け取り、意図を読み取る（「全部OK」「#131 だけやめて」「2つだけ」「#131 のこれどういう意味？」など）。返事の回で行うのは次だけとする。

- OK：指した項目に`approved`を記録する。「#131 だけやめて」のように一部だけ外す返事は、その項目を取り消し、残りをすべてOKとする。
- 取り消し：OKがあれば`approval_revoked`、未使用の`planned`に`plan_cancelled`（どちらもnote：返事で取り消し）を記録する。
- 量：`amount`に書く。枠が増えて載せられる項目があれば追加分として見せる。
- 休み：未使用の`planned`をすべて取り消しと同じに扱う。退勤時刻は記録しない。
- 問い：予定・台帳・Issue・PRから説明する。状態は変えない。

OKと取り消しが効くのは、そのスレッドの予定と追加分で見せた新規起動の項目のうち、未使用の`planned`があるものだけとする。続行と先に聞きたいことには効かない。先に聞きたいことへの答えをスレッドで受けたら、Issueにコメントするよう伝える（workerがGitHubから読むため）。
指している項目や意図が一つに決まらない返事では何も記録せず、どう受け取ればよいかを聞き返す。起動済みの項目を取り消されたときは記録を変えず、Appで止めるよう伝える。
返事を処理したら、何をOKし、何をやめ、何を始めたかを[スレッドでのやりとり](digest.md#スレッドでのやりとり)の書き方で返す。

### OKの記録

OKは予定の一覧ではなく、Issueごとに`attempts`の`approved`で記録する。noteには、Issue本文の最終編集時刻と依存先（blocked by）のIssue番号を書く。
有効なOKとは、最後の`approved`のうち、次をすべて満たすものをいう。一度OKした項目は、有効なOKが残る限り次の日も聞き直さない。

- それより後に`approval_revoked`がない。
- それより後に、`ready`以外へ移る`status`の記録がない。
- Issue本文の最終編集時刻と依存先が、noteと同じである。

照合か起動の前に本文の編集か依存先の変化を見つけたら、`approval_revoked`（note：前提の変化）を記録する。返事の回なら、追加分としてOKを聞き直す。それ以外の回では、次の予定で聞き直す。

### 量

新規起動の枠は、`limits.max_unreviewed_drafts`から、未レビューのDraft PR（`review_ready`でPRがDraftのもののうち、[未対応のownerのレビュー](item.md#ownerのレビュー)がないもの）と`running`の項目の数を引いたもの（0未満なら0）とする。レビュー待ちが少ないほど多く始める。
`amount`があれば、今夜だけ次のように上書きする。今夜の起動数は、最新の予定より後の`launch_requested`の数とする。

- `more`：`max_unreviewed_drafts`を2倍にして数える。
- `less`：今夜の起動を1件までにする。
- 数：枠に関係なく、今夜の起動をその件数までにする。

### 追加分と外れた仕事

返事の回は、返事への応答に次のものを添える。

- 追加分：前提が変わってOKを聞き直す項目と、量の指定で枠が増えて載せられるようになった項目。`planned`を追記し、OKを聞く。すでにOKした項目は繰り返さない。
- 外れた仕事：未使用の`planned`のうち、`ready`でなくなったか[起動の確認](#起動の確認)を通らなくなった項目。`plan_cancelled`に変わった点を書き、今夜はやめたことを一言で伝える。

OK済みで枠が空くのを待つ項目は、夜の起動の回が起動する。翌朝までOKのない項目は、朝の段取りで閉じる。

## 起動の確認

予定の回で`ready`の項目を新規起動として予定に載せる前と、起動する直前に、次の確認をすべて行う。通らなければ、書いたとおりの`status`にして`attempts`に`status`を記録し、次の項目へ進む。

1. `worker_thread`が空である。値があれば新規起動にせず、[続行の送信](item.md#続行の送信)の理由`resume`で既存workerへの続行として扱う。
2. Issueに`owner`以外の担当者や、紐づく未mergeのPRがない。あれば`needs_decision`にする。
3. `harnexus-task state`（`--request`なし）の記録に、同じIssueを指す別のlaunchがない。taskIdが別の書き方（`#456`・`456`など）のものと、documentRefsに同じIssueのURLを含むものを探す。あれば`needs_decision`にする。
4. 依存先（blocked by）がすべて完了し、Issueが今も`sources`のクエリに当たる。依存先が未完了なら`ready`のまま`next_action`に依存先を書き、クエリに当たらなければ`needs_decision`にする。
5. `codex_app__list_projects`を一度呼び、`config.yaml`の`repos.<owner/repo>.path`と一致するprojectを選ぶ。一致がない、または複数あれば`needs_decision`にする。

## 起動の手順

返事と起動の回で使う。対象は、最新の予定と追加分の未使用の`planned`のうち、[有効なOK](#okの記録)のある項目とする。OKのない`planned`は起動せず、そのまま残す。
予定の優先順に1件ずつ、[量](#量)の枠が残る間だけ扱う。枠を超えた項目は`planned`のまま次の回に回す。
項目が`ready`でなくなっていれば起動せず、`plan_cancelled`に変わった点を書く。上の確認を通らなかった`planned`も、`plan_cancelled`に確認の番号を書いて閉じる。

新規起動は、上の確認をすべて通ったものだけ次の順に進める。

1. `requests/<file>.json`を[起動依頼JSON](../../task-session-launch/references/request.md)の書式で作る。
   - `taskId`：keyから`gh:`を除いた値（例：`org/repo#456`）。
   - `documentRefs`：子IssueのURL、umbrella IssueのURLの順。umbrellaがなければ子IssueのURLだけ。
   - `completionTarget`：`draft_pr`に固定する。
   - `projectId`：確認5で選んだもの。
2. 台帳を`running`にし、`attempts`に`launch_requested`を追記してファイルへ書く。
3. [task-session-launch](../../task-session-launch/SKILL.md)の手順3・4で`harnexus-task launch`を実行する。同じprojectIdとtaskIdなら既存workerが返るため、同じkeyは同じworkerになる。
4. 出力の`threadId`を`worker_thread`に書き、`attempts`に`launched`を`threadId`付きで追記してファイルへ書く。
5. 結果不明・モデル不一致・起動失敗は再実行しない。`needs_decision`にして、`next_action`にAppで確認する内容を書く。承認されずに実行できなかった場合は`failed`で記録し、この実行では以後の起動と送信をしない。

起動した後は待たずに次の項目へ進む。
