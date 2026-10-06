[$ai-code-review]({skill_path})
タスクID: {task_id}
参照文書のパス・URL:
{document_refs}
workerの担当AI: {worker_ai}
workerのチャットID: {worker_chat_id}
workerの作業ディレクトリ: {checkout}
レビュー対象のコミット範囲: {base}...{head}
PRのURL: {pr_url}

worker checkoutでレビューし、branchやcheckoutは変更しないでください。
受信メタデータにsource_thread_idがあればworkerのチャットIDと照合し、不一致は判定保留にしてください。
ローカル固定SHA差分をレビューし、PRとCIはPRのheadが候補SHAと一致する場合だけ根拠にしてください。
base branchが進んだことだけを理由にLGTMを保留しないでください。
