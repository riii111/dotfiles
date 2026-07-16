---
name: code-review
description: |
  実装済みの変更を、正しさ・一貫性・設計・保守性・安全性・実用上の品質の観点で徹底的にレビューする。
  PR、ブランチ差分、ローカル差分のレビューや、投稿可能なレビューコメントの作成に使う。
  軽微でも actionable な指摘を省略せず、調査過程や取り下げた候補は出力しない。
---

# code-review

レビューだけを行う。実装、通知、PR 作成は行わない。

## Review lanes

- `single`: 既定。本体だけで全観点を徹底的にレビューする
- `double`: 本体と subagent 1体で観点を分担し、本体が重複を除いて統合する

指定がなければ `single` とする。「徹底的に」「大規模」などの表現だけで `double` にしない。

`double` では差分に応じて subagent の担当を選ぶ。たとえば本体が correctness と設計を、subagent が consistency、test、security のうち関連する観点を担当する。subagent summary をそのまま出力せず、本体が根拠を確認する。

## Review workflow

1. ユーザーが指定した PR、diff range、base をレビュー範囲の authority とする。
2. 指定がなければ PR と repo の状態から対象差分を特定する。安全に特定できない場合だけ質問する。
3. 適用される repo instructions、タスク資料、仕様、参考 PR を先に読む。
4. `memo/learnings` が存在する場合は、変更箇所やタスクに関連する資料だけを読んで観点へ反映する。全件を無条件に読み込まない。現在の仕様と repo instructions を優先する。
5. 差分だけで判断せず、必要な call site、近傍実装、test、設定、公開 API への影響を確認する。
6. actionable な finding を出し切るまで correctness、設計、命名、一貫性、test gap、dead code、保守性、性能、NITs を確認する。

レビューモードや focus area を定型質問しない。不明点がレビュー結果を変える場合だけ質問する。

## Security review

差分とコンテキストから必要性を判断し、関連する場合は安全性の観点を自動的に追加する。別引数は要求しない。

主な対象:

- auth / authz / tenant boundary
- untrusted input / parsing / deserialization
- secret / credential / config handling
- SQL / shell / process execution
- file path / permission / unsafe operation
- external network / webhook / redirect
- cryptography / token / session

`single` では本体が確認する。`double` ではリスクに応じて subagent の担当へ security を含める。

## Validation

PR がある場合は `gh pr view --json` で CI 状態を確認する。CI が緑、またはユーザーが CI で担保済みと示した場合は、ローカルで test や linter を再実行しない。

dirty worktree がある場合はレビュー結果の後で簡潔に知らせる。CI の SHA とローカル差分の厳密な照合は必須にしない。

CI がない、または失敗中でも、網羅的な check を機械的に実行しない。finding の妥当性確認に必要な場合だけ対象を絞って実行する。

## Output format

通常は次の枠で返す:

- `Blocking`
- `Non-blocking`

件数上限を設けない。軽微な命名、可読性、一貫性、test readability も、今の差分で直す価値があり具体的に修正できるなら `Non-blocking` に含める。

`Blocking` と `Non-blocking` には、投稿可能で actionable なレビューコメントだけを書く。次は出力しない:

- 実装が妥当だと確認できた調査結果
- 修正を求めない subagent summary
- 実行していない test / check
- 具体的な変更要求ではない前提や注意点
- finding として検討したが、根拠不足や誤検知として取り下げた候補

レビュー範囲の制限、dirty worktree、外部依存など、結果の解釈を変える caveat だけは末尾に短く添える。対応が必要なら caveat ではなく具体的な finding にする。指摘が1件もなければ、明示的に `LGTM` と返す。
