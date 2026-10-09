# 起動

`ready`の項目は、次の確認をすべて通ったものだけ起動する。通らなければ、書いたとおりの`status`にして次の項目へ進む。

1. `worker_thread`が空である。値があれば起動せず、`needs_decision`にして`next_action`に「既存workerへの続行をAppで指示する」と書く。
2. Issueに`owner`以外の担当者や、紐づく未mergeのPRがない。あれば`needs_decision`にする。
3. `harnexus-task state`（`--request`なし）の記録に、同じIssueを指す別のtaskId（`#456`・`456`など手動運用の書き方）がない。あれば`needs_decision`にする。
4. `codex_app__list_projects`を一度呼び、`config.yaml`の`repos`に書いたパスと一致するprojectを選ぶ。一致がない、または複数あれば`needs_decision`にする。

確認を通ったら、次の順に進める。

1. `requests/<file>.json`を[起動依頼JSON](../../task-session-launch/references/request.md)の書式で作る。
   - `taskId`：keyから`gh:`を除いた値（例：`org/repo#456`）。
   - `documentRefs`：子IssueのURL、umbrella IssueのURLの順。umbrellaがなければ子IssueのURLだけ。
   - `completionTarget`：`draft_pr`に固定する。
   - `projectId`：確認4で選んだもの。
2. 台帳を`running`にし、`attempts`に`launch_requested`を追記してファイルへ書く。
3. [task-session-launch](../../task-session-launch/SKILL.md)の手順3・4で`harnexus-task launch`を実行する。同じprojectIdとtaskIdなら既存workerが返るため、同じkeyは同じworkerになる。
4. 出力の`threadId`を`worker_thread`に書き、`attempts`に`launched`を`threadId`付きで追記してファイルへ書く。
5. 結果不明・モデル不一致・起動失敗は再実行しない。`needs_decision`にして、`next_action`にAppで確認する内容を書く。承認されずに実行できなかった場合は`failed`で記録し、この実行では以後の起動をしない。

起動した後は待たずに次の項目へ進む。
