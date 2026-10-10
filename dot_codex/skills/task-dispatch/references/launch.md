# 起動

## 起動の確認

予定の回で`ready`の項目を新規起動として予定に載せる前と、起動の回で起動する直前に、次の確認をすべて行う。通らなければ、書いたとおりの`status`にして`attempts`に`status`を記録し、次の項目へ進む。

1. `worker_thread`が空である。値があれば新規起動にせず、[続行の送信](item.md#続行の送信)の理由`resume`で既存workerへの続行として扱う。
2. Issueに`owner`以外の担当者や、紐づく未mergeのPRがない。あれば`needs_decision`にする。
3. `harnexus-task state`（`--request`なし）の記録に、同じIssueを指す別のlaunchがない。taskIdが別の書き方（`#456`・`456`など）のものと、documentRefsに同じIssueのURLを含むものを探す。あれば`needs_decision`にする。
4. `codex_app__list_projects`を一度呼び、`config.yaml`の`repos.<owner/repo>.path`と一致するprojectを選ぶ。一致がない、または複数あれば`needs_decision`にする。

## 起動の回の手順

[SKILL](../SKILL.md#起動)の条件に合う`planned`を、予定の優先順に1件ずつ扱う。先に[予定の取り消し](item.md#予定の取り消し)の条件を確かめ、当たれば次の項目へ進む。
扱った`planned`は、起動か送信をしなかった場合も、`plan_cancelled`に理由（確認の番号、続行の手順の番号など）を書いて閉じる。

新規起動は、項目が`ready`のままで、上の確認をすべて通ったものだけ次の順に進める。`ready`でなくなっていれば起動せず、`plan_cancelled`に変わった点を書く。

1. `requests/<file>.json`を[起動依頼JSON](../../task-session-launch/references/request.md)の書式で作る。
   - `taskId`：keyから`gh:`を除いた値（例：`org/repo#456`）。
   - `documentRefs`：子IssueのURL、umbrella IssueのURLの順。umbrellaがなければ子IssueのURLだけ。
   - `completionTarget`：`draft_pr`に固定する。
   - `projectId`：確認4で選んだもの。
2. 台帳を`running`にし、`attempts`に`launch_requested`を追記してファイルへ書く。
3. [task-session-launch](../../task-session-launch/SKILL.md)の手順3・4で`harnexus-task launch`を実行する。同じprojectIdとtaskIdなら既存workerが返るため、同じkeyは同じworkerになる。
4. 出力の`threadId`を`worker_thread`に書き、`attempts`に`launched`を`threadId`付きで追記してファイルへ書く。
5. 結果不明・モデル不一致・起動失敗は再実行しない。`needs_decision`にして、`next_action`にAppで確認する内容を書く。承認されずに実行できなかった場合は`failed`で記録し、この実行では以後の起動と送信をしない。

続行は、照合で確かめた理由・head・refが予定と同じものだけ、[続行の送信](item.md#続行の送信)の手順1〜5で送る。`resume`は照合で理由を出し直さないため、項目が`ready`のままで`worker_thread`が予定のときと同じなら送る。違えば送らず、`plan_cancelled`に変わった点を書く。`resume`を送ったら`running`にし、`status`を記録する。

起動・送信した後は待たずに次の項目へ進む。
