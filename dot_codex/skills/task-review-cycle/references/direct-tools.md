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
独立reviewerには[ai-code-review](../ai-code-review/SKILL.md)を渡す。依頼文のリンク先は、このSKILLのインストール先から解決し、実在を確認した絶対パスへ置き換える。

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
   LGTM後は[task-worker](../task-worker/SKILL.md)の手順へ戻る。

## Claude workerの受取手順

1. 作成したreview Taskの`threadId`を`wait_threads`の`targets`に渡し、`timeoutMs`は60000以下にする。
   返されたcursorは次回の`afterCursor`へ渡す。timeoutは失敗やLGTMとして扱わず、待機を続ける。
2. 完了時の回答を受け取り、不足する場合は同じ`threadId`を`read_thread`で読む。
   commentaryや途中経過だけでは判定せず、回答の比較範囲が依頼したreview base SHAとhead SHAに一致することを確認する。
3. Blockingをまとめて修正し、影響検証とcommitを行い、同じreview Taskへ再レビューを依頼する。
   判定保留なら不足を解消して同じreview Taskで続ける。LGTMならtask-workerの最終検証・Draft PR・CI確認へ進む。

初回・再レビューとも、reviewerへの返信要求やturn終了による返信待ちは行わない。

## 依頼文

```text
[$ai-code-review](/Users/a81803/.codex/skills/ai-code-review/SKILL.md)
worker実行主体: <Claude / Codex>
worker Task ID: <worker Task ID>
worker checkout: <worker checkoutの絶対パス>
PR: <PR URLまたは未作成（ローカル差分レビュー）>
候補状態: <未push / push済み>
review base SHA: <review base SHA>
head SHA: <head SHA>
比較範囲: <review base SHA>...<head SHA>
事前コンテキスト: <課題・期待する挙動・制約・対象外、および管理元の該当節への参照>

事前コンテキストとworker checkoutの適用規約を読んでからレビューを開始してください。
現在の比較範囲全体をレビューしてください。
Gitの読み取り、コード読取、必要な検証はworker checkoutを作業ディレクトリにして行ってください。
branchやcheckoutは変更しないでください。
worker checkoutのHEADが指定head SHAと一致することを確認してください。
候補がpush済みでPRがある場合は、PR headが指定head SHAと一致することを確認してください。
不一致ならLGTMを出さずworkerへ伝えてください。
一致した場合は、そのheadに対するCI状態も確認してください。
それ以外（候補が未push、またはPR未作成）は、指定範囲のローカル差分をレビューしてください。
既存PRがあっても、今回候補が未pushならPR headやCIをレビューの根拠にしないでください。
再レビューでも前回の指摘だけに限定せず、新しい問題がないか確認してください。
review開始後にbase branchが進んでも、それだけを理由にLGTMを保留しないでください。
PRへの投稿、修正、Ready化、mergeは行わないでください。
```

共通の依頼文に、workerの実行主体に応じた次の返却指示を追加する。

### Claude workerへの返却指示

```text
ai-code-reviewの対象SHA・判定・指摘・検証結果を、このreview Taskの最終回答として返してください。
workerがwait_threads/read_threadで受け取るため、workerへのmessage送信は行わないでください。
```

### Codex workerへの返却指示

worker Taskへ返すmessageは次の形式にするよう依頼する。

```text
$task-review-cycle

<ai-code-review の対象SHA・判定・指摘・検証結果>
```

この`$task-review-cycle`はCodex worker Taskへのmessageの先頭に置く文字列であり、reviewerは適用しない。
reviewerはリンクで渡したai-code-reviewでレビューする。

```text
レビュー完了後、`codex_app__send_message_to_thread`の`threadId`にworker Task IDを指定して結果を返してください。
送信が受理されたことを確認したらreviewerのturnを終了してください。
```

## 制約

Codex workerはreviewerから`$task-review-cycle`で始まるmessageが届くことで新しいturnが始まり、同じSKILLを適用して指摘確認、修正、再レビューを行う。

reviewerは固定された比較範囲の実装を判定する。
base branchのtipがreview中に進んだこと自体は指摘やLGTM保留の理由にしない。
現在のbaseとの競合や意味的重複を実際に確認した場合だけ、その具体的根拠をworkerへ返す。

既定はmanualであり、明示許可なしにReady化やmergeをしない。
許可された場合だけ、最新headと必要なchecksを再確認して実行する。
再開時は既存の会話、PR、worktree、review Taskを観測して続ける。
