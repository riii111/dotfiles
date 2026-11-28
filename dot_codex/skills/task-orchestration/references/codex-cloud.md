# Codex Cloud workerをローカルから追う

管理元のリポジトリを `owner/repo`、タスクIDを管理元の表記で渡す。
コマンドの `<helper>` はこの文書と同じ場所にある [codex-cloud-worker.py](codex-cloud-worker.py) の絶対パスに置き換える。

1. `python3 <helper> get <owner/repo> <task-id>` で登録を確認する。
   - `attached` なら、保存された `hostId` と `threadId` を `mcp__codex_app__wait_threads` に渡す。
     履歴は `read_thread`、許可された追加指示は `send_message_to_thread` を同じIDで行う。
     別のworkerは起動しない。
   - `pending` なら、すでに開いたCloudチャットのURLをユーザーから受け取って手順3へ進む。
     URL待ちの間は起動を繰り返さない。
   - `null` なら通常どおり起動可否を判断する。
     すでにローカルworkerがあるtaskはそのworkerを追う。
   - 登録を読めなければ、その理由を報告する。
2. Codex Cloudでの実行を指定されたtaskは、`python3 <helper> prepare <owner/repo> <task-id>` で手動起動を予約する。
   `created: true` のときだけ、[起動依頼](../../task-session-launch/references/worker.md)に対象リポジトリ、開始branch、`task-worker`の「Codex Cloud」に従う指示を添えてユーザーに渡す。
   Codex Cloudの画面でその依頼を使ってタスクを1つ起動し、URLを返してもらう。
   参照文書は開始branchに含まれるパスかCloudから読めるURLを使う。
3. URLのチャットIDを `mcp__codex_app__read_thread` に `hostId: durable` とともに渡し、起動依頼のタスクID・リポジトリを照合する。
   一致したIDを `python3 <helper> attach <owner/repo> <task-id> <thread-id>` で登録し、手順1の `attached` に従って追う。
   登録済みの別IDとの衝突はその場で報告する。

起動に失敗した場合は、ユーザーとCloudチャットが作られていないことを確認してから `python3 <helper> cancel <owner/repo> <task-id>` で予約を解除する。
登録はローカルのXDG stateディレクトリに保存され、同じMac上の別の統括チャットやcheckoutからも読み出せる。
サンドボックスから状態ディレクトリへ書けない場合は、`prepare`、`attach`、`cancel` を既定の承認経路で実行する。
