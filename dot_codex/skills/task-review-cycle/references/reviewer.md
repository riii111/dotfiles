[$ai-code-review]({skill_path})
worker実行主体: {worker}
worker Task ID: {worker_thread_id}
worker checkout: {checkout}
PR: {pr}
候補状態: {push_state}
比較範囲: {base}...{head}
事前コンテキスト: {context}

ai-code-reviewに従い、worker checkoutでレビューしてください。branchやcheckoutは変更しないでください。
候補がpush済みでPRがある場合はPR headの一致と、そのheadのCI状態を確認してください。
未pushまたはPR未作成の場合はローカル固定SHA差分を根拠にし、既存PRのheadやCIを根拠にしないでください。
base branchが進んだことだけを理由にLGTMを保留しないでください。
