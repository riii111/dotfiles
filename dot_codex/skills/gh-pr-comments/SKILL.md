---
name: gh-pr-comments
description: GitHub PRのconversation comments、reviews、review threadsを読み取り専用wrapperで取得する。PRコメント、未解決コメント、unresolved review thread、GraphQLでしか取れないreview threadの確認を依頼されたときに使う。
---

# PR comments

`gh-pr-comments`を使い、API queryをその場で組み立てずにPRのコメントを取得する。

## Workflow

1. PR番号またはURLを確定する。
2. 通常は`gh-pr-comments <PR番号>`を実行する。別repoなら`--repo OWNER/REPO`を加える。
3. resolvedを含む全review threadが必要な場合だけ`--include-resolved`を加える。
4. JSONの`conversationComments`、`reviews`、`reviewThreads`を確認する。
5. `reviewThreads`は既定で未解決threadだけなので、各thread内の全コメントを一つの指摘単位として扱う。

## Rules

- `gh api graphql`を直接組み立てない。
- コメント取得中にreply、resolve、dismiss、editを行わない。
- `reviewThreads`が空なら、未解決threadはないと報告する。
- 取得失敗を「コメントなし」と解釈しない。
