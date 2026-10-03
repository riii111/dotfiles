[$ai-code-review]({skill_path})
worker Task ID: {worker_thread_id}
worker checkout: {checkout}
PR: {pr}
候補状態: {push_state}
review base SHA: {base}
head SHA: {head}
比較範囲: {base}...{head}
事前コンテキスト: {context}

ai-code-reviewとworker checkoutの適用規約を読み、指定範囲全体を独立レビューしてください。
Gitの読み取り・コード読取・必要な検証はworker checkoutで行い、branchやcheckoutは変更しないでください。
checkoutのHEADが指定head SHAと一致しない場合は判定保留にしてください。
候補がpush済みでPRがある場合はPR headの一致と、そのheadのCI状態を確認してください。
未pushまたはPR未作成の場合はローカル固定SHA差分を根拠にし、既存PRのheadやCIを根拠にしないでください。
再レビューも比較範囲全体を確認してください。base branchが進んだことだけを理由にLGTMを保留しないでください。
PRへの投稿、修正、Ready化、mergeは行わないでください。
ai-code-reviewの対象SHA・判定・指摘・検証結果をこのreview Taskの最終回答として返してください。
workerはCLIで回答を取得するため、workerへのmessage送信は行わないでください。
