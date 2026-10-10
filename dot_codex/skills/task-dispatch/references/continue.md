# 既存workerへの続行

夜の実行で既存workerへ追加指示を送る。予定作成では、続行を送れるかの確認だけに使う。
対象は、人の判断を待たずに続行するだけで進むものに限り、OKは要らない。

| 理由 | 条件 | ref |
| --- | --- | --- |
| stopped | `running`で、worker_threadの最新turnが人の判断を求めない最終回答で止まっている（CIの失敗での停止など） | なし |
| review | [未対応のownerのレビュー](item.md#ownerのレビュー)がある | レビューのID |
| resume | `needs_decision`から再判定で`ready`になり、`worker_thread`に値がある（[起動の確認](launch.md#起動の確認)の1） | 再判定のきっかけにしたコメントのID、Issueの更新時刻、またはメモに追記した時刻 |

送るかどうかは、`attempts`の`continue_sent`だけで決める。
次の表を上から当てはめ、最初に当たった行の扱いにする。
起動の回は表のとおりに送る。
予定の回は送らず、表で「送る」に当たるものを見込みとして予定に書く。

| 行 | 状況 | 扱い |
| --- | --- | --- |
| 1 | workerの最新turnが進行中 | 送らず、次の起動の回に持ち越す |
| 2 | 同じ理由・同じhead・同じrefの`continue_sent`があり、その送信より後にworkerのturnが終わっている | 送らない。送っても進まなかったものとして`needs_decision`にし、止まった位置と送った内容を`next_action`に書く |
| 3 | 同じ理由・同じhead・同じrefの`continue_sent`があり、その送信より後のturnがない | 送らない。届いていない可能性があるため`needs_decision`にし、Appで確かめる内容を`next_action`に書く |
| 4 | 同じ理由の`continue_sent`が、最後に`review_ready`へ移した後（なければ最後の`launched`の後）に`limits.max_continues`件ある | 送らずに`needs_decision`にし、繰り返し止まった位置を`next_action`に書く |
| 5 | 上のどれでもない | 送る |

送るときは、`attempts`に`continue_sent`を追記してファイルへ書いてから、`codex_app__send_message_to_thread`の`threadId`に`worker_thread`を指定して送る。
同じ項目に複数の理由があれば1通にまとめ、`continue_sent`は理由ごとに書く。
送信が受理されたことを確かめられなければ（エラー・タイムアウトを含む）再送しない。
`failed`を記録して`needs_decision`にし、Appで送信の有無を確かめる内容を`next_action`に書く。

`resume`を送ったら`running`にし、`status`を記録する。
messageの先頭に`$task-worker`を置き、PRのURL・head・理由・refを自分の言葉で書く。
[決めたことのメモ](launch.md#決めたことのメモ)があれば、その絶対パスも書く。
レビューや回答の文面は転記せず、workerがGitHubから読む。
