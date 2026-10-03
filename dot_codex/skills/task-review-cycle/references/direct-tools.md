初回にreview Taskを作成するときは、`model`に`gpt-6.1-sol`、`thinking`に`medium`を指定する。
再レビューでは`model`と`thinking`を指定せず、同じreview Taskの現在設定を維持する。
ユーザーがmodelまたはreasoning effortを明示した場合だけ、その依頼で対応する値を指定する。
Claude workerがharnexusから作成するreviewerはCodexモデルに限られる。Claudeモデルを明示された場合は、その制約を伝えて対応するモデルの指定を求める。

## 実行主体とツール

worker自身の実行主体で結果の受取方法を選び、reviewerへの依頼にも明記する。

| worker | 使用するツール | 結果の受取方法 |
| --- | --- | --- |
| Claude | harnexusが提供する`list_projects`、`create_thread`、`send_message_to_thread`、`wait_threads`、`read_thread` | workerが待機し、reviewerの回答を読む |
| Codex | `codex_app__list_projects`、`codex_app__create_thread`、`codex_app__send_message_to_thread` | reviewerがworkerへ返信し、新しいturnを開始する |

以下の`codex_app__`付きのツール名は、Claude workerでは表の対応する提供ツールに読み替える。
Claude workerは自身が`create_thread`で作成したreview Taskへ再レビューを送る。
独立reviewerには[ai-code-review](../../ai-code-review/SKILL.md)を渡す。依頼文のリンク先は、このSKILLのインストール先から解決し、実在を確認した絶対パスへ置き換える。

## 初回手順

1. worker checkoutのrepositoryに対応するprojectと`isGitRepository`を`codex_app__list_projects`で解決する。
   Git repositoryなら`target: { type: "project", projectId: <resolved projectId>, environment: { type: "worktree" } }`を指定する。
   非Gitなら同じ`type`と`projectId`に`environment: { type: "local" }`を指定する。
   `codex_app__create_thread`を一度呼ぶ。
   親・worker Taskはforkせず、freshなproject Taskとして過去の会話を引き継がない。
   - `title`はworkerと同じ識別子で`Review <identifier>`とし、PR titleやtask titleを含めない。
   - `prompt`には下記の共通依頼文と、workerの実行主体に対応する返却指示だけを使い、worker Task ID、worker checkout、候補のpush状態、review base SHA、head SHA、PR URLまたは未作成であることを渡す。
     課題・期待する挙動・制約・対象外と、その根拠となる管理元の該当節だけを事前コンテキストに含める。
     実装者の思考履歴、過去サイクル、前回のレビュー結果は含めない。
   - PR作成前の候補もローカル差分としてレビューする。
     各候補はcommit済みのhead SHAで指定する。
2. 返された`threadId`を再レビュー用に保持する。
   初回依頼を別messageで重複送信しない。
   Codex workerはturnを終了する。Claude workerは下記の受取手順を続ける。

## 再レビュー手順

1. 同じreview Taskへ`codex_app__send_message_to_thread`で共通依頼文と、workerの実行主体に対応する返却指示だけを送る。
   worker Task ID、worker checkoutの絶対パス、候補のpush状態、固定したreview base SHA、最新のhead SHA、PR URLまたは未作成であることを入れる。
2. 前回の指摘は依頼文へ書かない。
3. 再レビューのたびに所定の全検証やpushを要求しない。
   worker Taskは必須修正をまとめて対応し、影響する検証を行った新しいcommitを依頼する。Non-blocking は任意であり、未対応だけではサイクルを継続しない。
4. Codex workerはreview依頼を送った時点でturnを終了する。Claude workerは下記の受取手順を続ける。
   LGTM後は[task-worker](../../task-worker/SKILL.md)の手順へ戻る。

## Claude workerの受取手順

1. 作成したreview Taskの`threadId`を`wait_threads`の`targets`に渡し、`timeoutMs`は60000以下にする。
   返されたcursorは次回の`afterCursor`へ渡す。timeoutは失敗やLGTMとして扱わず、待機を続ける。
2. 完了時の回答を受け取り、不足する場合は同じ`threadId`を`read_thread`で読む。
   commentaryや途中経過だけでは判定せず、回答の比較範囲が依頼したreview base SHAとhead SHAに一致することを確認する。
3. Blockingをまとめて修正し、影響検証とcommitを行い、同じreview Taskへ再レビューを依頼する。
   判定保留なら不足を解消して同じreview Taskで続ける。LGTMならtask-workerの最終検証・Draft PR・CI確認へ進む。

初回・再レビューとも、reviewerへの返信要求やturn終了による返信待ちは行わない。

## 依頼文

[共通テンプレート](reviewer.md)を読み、すべてのplaceholderを今回の依頼情報で埋める。`skill_path`は実在を確認したai-code-review/SKILL.mdの絶対パス、`worker`は`Codex`または`Claude`、`worker_thread_id`はworker自身の確定Task IDとする。
`checkout`はworker checkoutの絶対パス、`base`・`head`は固定した完全SHA、`push_state`は候補のpush状態、`pr`はPR URLまたは未作成であること、`context`は課題・期待する挙動・制約・対象外と管理元の該当節を入れる。

workerの実行主体に応じて、次の返却指示を共通テンプレートの末尾へ追加する。CLI経路も同じファイルを使う。

- Claude: [最終回答の返却指示](reply-claude.md)
- Codex: [workerへの返信指示](reply-codex.md)

reply-codex.mdの`$task-review-cycle`はworkerへ返すmessageの先頭に置く文字列であり、reviewerは適用しない。reviewerはリンクで渡したai-code-reviewを使う。

## 制約

Codex workerはreviewerから`$task-review-cycle`で始まるmessageが届くことで新しいturnが始まり、同じSKILLを適用して指摘確認、修正、再レビューを行う。

reviewerは固定された比較範囲の実装を判定する。
base branchのtipがreview中に進んだこと自体は指摘やLGTM保留の理由にしない。
現在のbaseとの競合や意味的重複を実際に確認した場合だけ、その具体的根拠をworkerへ返す。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
