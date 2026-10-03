# reviewctlの依頼JSON

`start`と`rerun`には次のJSONファイルを渡す。checkoutは実装worktreeの絶対パス、base/headは完全なcommit SHAとする。

```json
{
  "identifier": "task-id",
  "projectId": "repositoryのprojectId",
  "checkout": "/absolute/path/to/worker-checkout",
  "base": "固定したreview base SHA",
  "head": "commit済み候補のhead SHA",
  "pushed": false,
  "pr": null,
  "context": "課題・期待する挙動・制約・対象外と管理元の該当節"
}
```

projectIdは`reviewctl projects`の結果からrepositoryに対応するものを選ぶ。PRがある場合はprにURLを入れる。未push候補は、PRがあってもpushedをfalseにする。
`reviewctl`はcheckoutのHEADと指定headの一致を送信前に確認する。再レビューではprojectId・checkout・baseを維持し、候補headとpush/PR状態を更新する。

CLIは通常`HARNEXUS_THREAD_ID`または`CODEX_THREAD_ID`からworkerを識別する。実行環境から取得できない場合は`--caller-thread-id`でworker自身のIDを指定する。

接続先は`HARNEXUS_LINK_SOCKET`を使い、未設定ならharnexusのlinkディレクトリから稼働中のsocketを探す。複数ある場合は`--socket`を指定する。Claudeのsession tokenは環境変数から読み、状態ファイルには保存しない。

CLIの状態は現在のworktreeのGitディレクトリに保存する。別の状態を使う場合は`--state <絶対パス>`を全コマンドで指定する。`--socket`・`--state`・`--caller-thread-id`はサブコマンドより前に置く。
`wait`のstatusは`pending`（再度待つ）、`review_available`（最終回答を判断する）、`needs_attention`（失敗・中断を確認する）。最終回答のSHAと判定を読んで判断し、CLIの成功終了だけをLGTMと扱わない。

書込結果が不明な場合はAppを確認し、ユーザーが既存reviewerの採用を明示した場合だけ`reviewctl recover --reviewer-thread-id <確定ID>`を使う。harnexus側で以前の書込が未確定の間は、復旧後も追加の書込みが拒否されることがある。
