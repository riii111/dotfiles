# reviewctlの依頼JSON

`prepare`と`record`には同じJSONファイルを渡す。checkoutは実装worktreeの絶対パス、base/headは完全なcommit SHAとする。

```json
{
  "identifier": "task-id",
  "worker": "Codex",
  "workerId": "worker自身の確定Task ID",
  "projectId": "repositoryのprojectId",
  "checkout": "/absolute/path/to/worker-checkout",
  "base": "固定したreview base SHA",
  "head": "commit済み候補のhead SHA",
  "pushed": false,
  "pr": null,
  "context": "課題・期待する挙動・制約・対象外と管理元の該当節"
}
```

workerは`Codex`または`Claude`。projectIdは既存のlist_projectsでGit repositoryに対応するものを選ぶ。PRがある場合はprにURLを入れ、未push候補はPRがあってもpushedをfalseにする。
再レビューではheadとpush/PR状態を更新し、worker・workerId・projectId・checkout・baseを維持する。

- `reviewctl prepare --request request.json`: HEADと指定headの一致、tracked変更がないことを確認し、既存ツールへ渡すJSONを標準出力する。送信・状態更新は行わない。
- `reviewctl record --request request.json --reviewer-thread-id <確定ID>`: ツールの送信受理を確認した後で、reviewerと候補を保存する。初回・再レビューとも送信に使ったJSONを渡す。
- `reviewctl state`: 最後に記録したreviewerと候補を読む。回答やLGTMの記録ではない。

状態は実行中のworktreeのGitディレクトリに保存する。同じworktreeでコマンドを実行する。別の状態を使う場合は`--state <絶対パス>`をサブコマンドより前に置き、全コマンドで同じ値を使う。
SKILLの場所を明示する場合は`--skills-root <skillsディレクトリ>`をサブコマンドより前に置く。既定は`$CODEX_HOME/skills`または`~/.codex/skills`。

prepareはAPIを実行しないため、送信成否やreviewer IDの実在はworkerがツール結果で確認する。結果不明の送信はAppで確認するまで再送しない。モデル・thinkingの変更はユーザーが指定した場合だけprepareに渡す。
