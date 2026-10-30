# Cloudの独立レビュー引き渡し依頼

統括Codexが、独立したCodex reviewerへこの文書を渡す。
文書だけでレビューが始められるよう、すべての項目を実際の値で埋める。

- タスクID：
- 実装者：Claude（`harnexus-task claude`のセッションIDを併記）
- checkout：絶対パス。
  Cloudタスクが同じなら、そのまま読める場所
- base branch・base SHA：
- head SHA：
- PR URL：なければ`null`
- 参照文書：先頭をタスク管理元とする。
  パスまたはHTTPS URLを1行ずつ
- 実行した検証とその結果：コマンド、終了状態、未実行の検証とその理由
- 既知の未確認事項：

## レビュアーへの指示

[レビュー時の確認事項](../SKILL.md#レビュー時の確認事項)に従い、固定したbase/head SHAを使い、merge-baseから候補headまでのPR差分をレビューする。
上流の変更は、候補と合成した結果への影響を確認する。
checkoutに入れない場合は、入れないと述べて判定保留にし、LGTMにしない。
返却は[reply-Codex.md](reply-Codex.md)に従う。
結果には必ずbase SHAとhead SHAを書き、判定をLGTM・指摘あり・判定保留のいずれかで示す。
