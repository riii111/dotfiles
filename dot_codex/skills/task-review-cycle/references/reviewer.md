[$ai-code-review]({skill_path})
worker実行主体: {worker}
worker Task ID: {worker_thread_id}
worker checkout: {checkout}
PR: {pr}
候補状態: {push_state}
比較範囲: {base}...{head}
事前コンテキスト: {context}

worker checkoutでレビューし、branchやcheckoutは変更しないでください。
受信メタデータにsource_thread_idがあればworker Task IDと照合し、不一致は判定保留にしてください。
PRとCIはpush済み候補の同一headだけを根拠にしてください。未push候補はローカル固定SHA差分をレビューしてください。
base branchが進んだことだけを理由にLGTMを保留しないでください。
