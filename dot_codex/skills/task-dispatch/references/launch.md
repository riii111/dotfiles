# 承認と起動

## 承認

### OKの受け取り方

返事は自由な文として意図を読み取り、次の表に従う。
応答例は[スレッドでのやりとり](digest.md#スレッドでのやりとり)を参照する。

| 返事 | すること |
| --- | --- |
| OK | 指した項目に`approved`を記録する。「#131 だけやめて」のように一部だけ外す返事は、その項目を取り消し、残りをすべてOKとする |
| 取り消し | OKがあれば`approval_revoked`、未使用の`planned`に`plan_cancelled`を記録する（どちらもnote：返事で取り消し） |
| 量 | 言われたとおりに受け取り、`amount`に短く書く。何件にすればよいか分からなければ聞き返す。枠が増えて載せられる項目があれば追加分として見せる |
| 先に聞きたいことへの答え | [決めたことのメモ](#決めたことのメモ)に残し、その項目を判定し直す。`ready`になれば改めてOKを聞かず、`planned`（note：`launch 答え`）と`approved`（note：`答え`）を記録して、ほかのOKと同じく枠の範囲でその場で起動する。`ready`にならなければ、何が足りないかを返す |
| 休み | 未使用の`planned`をすべて取り消しと同じに扱う。退勤時刻は記録しない |
| 問い | 予定・台帳・Issue・PRから説明する。状態は変えない |

OKと取り消しが効くのは、そのスレッドの予定と追加分で見せた新規起動の項目のうち、未使用の`planned`があるものだけとする。続行には効かない。
答えとして受けるのは、その予定で聞いた問いへの答えだけとする。
指している項目や意図が一つに決まらない返事では何も記録せず、どう受け取ればよいかを聞き返す。
起動済みの項目を取り消されたときは記録を変えず、Appで止めるよう伝える。
返事を処理したら、何をOKし、何をやめ、何を始めたかを[スレッドでのやりとり](digest.md#スレッドでのやりとり)の書き方で返す。

### 決めたことのメモ

先に聞きたいことへの答えは、`~/agent-desk/decisions/<itemのファイル名>.md`に残す。
ownerがスレッドで答えた内容なので、判定では承認として扱う。
メモは人も読むため、YAMLや項目名の並びにせず、問い・決めたこと・理由をふつうの文で短く書く。
同じIssueで後から決め直したら、古い内容を消さずに日付を付けて追記する。
答えのない点や、問いと関係のない依頼は書かない。
GitHubには書き込まない。

```markdown
# org/pay#135 再送の状態を外部に公開する

2026-10-14：再送の状態は管理画面だけに出し、公開 API には足さない。外部の利用者から要望がまだなく、公開すると後から変えにくいため。
```

### OKの記録

OKは予定の一覧ではなく、Issueごとに`attempts`の`approved`で記録する。
有効なOKとは、最後の`approved`のうち、それより後に`approval_revoked`も、`ready`以外へ移る`status`の記録もないものをいう。
一度OKした項目は、有効なOKが残る限り次の日も聞き直さない。

### 新規起動する件数

新規起動の枠は、`limits.max_unreviewed_drafts`から次の件数を引き、0未満なら0とする。

- 未レビューのDraft PR：`review_ready`でPRがDraft、かつ[未対応のownerのレビュー](item.md#ownerのレビュー)がない項目。
- `running`の項目。

量について言われたら、今夜はその言葉どおりに数を決め、枠より優先する。
決まった読み替えはせず、何件にすればよいか分からなければスレッドで聞き返し、分かるまで`amount`に書かない。
今夜の起動数は、最新の予定より後の`launch_requested`の数とする。

### 追加分と外れた仕事

返事の回は、返事への応答に次のものを添える。

- 追加分：量の指定で枠が増えて載せられるようになった項目。
  `planned`を追記し、OKを聞く。すでにOKした項目は繰り返さない。
- 外れた仕事：未使用の`planned`のうち、`ready`でなくなったか[起動の確認](#起動の確認)を通らなくなった項目。
  `plan_cancelled`に変わった点を書き、今夜はやめたことを一言で伝える。

OK済みで枠が空くのを待つ項目は、夜の起動の回が起動する。
翌朝までOKのない項目は、朝の段取りで閉じる。

### 返事がなかった日

`no_reply: true`の日の夜の起動の回は、その予定と追加分の未使用の`planned`のうち、OKも取り消しもない項目にも`approved`（note：返事なし）を記録し、OKのある項目と同じく起動する。
先に聞きたいことが残る項目は`planned`にならないため、始めない。
退勤予定がCalendarにあった日と、退勤時刻の返事があった日は、OKのない項目を始めない。

## 起動の確認

予定の回で`ready`の項目を新規起動として予定に載せる前と、起動する直前に、次をすべて確かめる。
通らなければ表の扱いにし、`status`を変えたら`attempts`に記録して、次の項目へ進む。

| 確認 | 通らないとき |
| --- | --- |
| 1. `worker_thread`が空である | 新規起動にせず、[続行の送信](continue.md)の理由`resume`で既存workerへの続行として扱う |
| 2. Issueに`owner`以外の担当者や、紐づく未mergeのPRがない | `needs_decision` |
| 3. `harnexus-task state`（`--request`なし）の記録に、同じIssueを指す別のlaunchがない。taskIdが別の書き方（`#456`・`456`など）のものと、documentRefsに同じIssueのURLを含むものも探す | `needs_decision` |
| 4. 依存先（blocked by）がすべて完了し、Issueが今も`sources`のクエリに当たる | 依存先が未完了なら`ready`のまま`next_action`に依存先を書く。クエリに当たらなければ`needs_decision` |
| 5. `codex_app__list_projects`を一度呼び、`config.yaml`の`repos.<owner/repo>.path`と一致するprojectが1つだけある | `needs_decision` |

## 起動の手順

返事と起動の回で使う。
対象は、最新の予定と追加分の未使用の`planned`のうち、[有効なOK](#okの記録)のある項目とする。
OKのない`planned`は起動せず、そのまま残す。
予定の優先順に1件ずつ、[新規起動する件数](#新規起動する件数)の枠が残る間だけ扱う。
枠を超えた項目は`planned`のまま次の回に回す。
項目が`ready`でなくなっていれば起動せず、`plan_cancelled`に変わった点を書く。
上の確認を通らなかった`planned`も、`plan_cancelled`に確認の番号を書いて閉じる。

新規起動は、上の確認をすべて通ったものだけ次の順に進める。

1. `requests/<file>.json`を[起動依頼JSON](../../task-session-launch/references/request.md)の書式で作る。
   - `taskId`：keyから`gh:`を除いた値（例：`org/repo#456`）。
   - `documentRefs`：子IssueのURL、umbrella IssueのURLの順。
     umbrellaがなければ子IssueのURLだけ。
     [決めたことのメモ](#決めたことのメモ)があれば、末尾にその絶対パスを加える。
   - `completionTarget`：`draft_pr`に固定する。
   - `projectId`：確認5で選んだもの。
2. 台帳を`running`にし、`attempts`に`launch_requested`を追記してファイルへ書く。
3. [task-session-launch](../../task-session-launch/SKILL.md)の手順3・4で`harnexus-task launch`を実行する。
   同じprojectIdとtaskIdなら既存workerが返るため、同じkeyは同じworkerになる。
4. 出力の`threadId`を`worker_thread`に書き、`attempts`に`launched`を`threadId`付きで追記してファイルへ書く。
5. 結果不明・モデル不一致・起動失敗は再実行しない。
   `needs_decision`にして、`next_action`にAppで確認する内容を書く。
   承認されずに実行できなかった場合は`failed`で記録し、この実行では以後の起動と送信をしない。

起動した後は待たずに次の項目へ進む。
