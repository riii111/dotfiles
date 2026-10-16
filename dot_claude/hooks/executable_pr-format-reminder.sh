#!/bin/bash
# PreToolUse hook: block the first PR title/body write per session and return the PR format rules

input=$(cat 2>/dev/null) || exit 0
[[ -z "$input" ]] && exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[[ -z "$command" || -z "$session_id" ]] && exit 0

if [[ "$command" =~ gh[[:space:]]+pr[[:space:]]+create ]]; then
	:
elif [[ "$command" =~ gh[[:space:]]+pr[[:space:]]+edit ]] && [[ "$command" =~ (--title|--body|--body-file|[[:space:]]-t[[:space:]]|[[:space:]]-b[[:space:]]|[[:space:]]-F[[:space:]]) ]]; then
	:
else
	exit 0
fi

# Marker lives outside the repo so the reminder fires once per session regardless of cwd.
# mkdir is atomic, so only one of concurrent hook processes returns the reminder.
marker_dir="${TMPDIR:-/tmp}/claude-pr-format-reminder"
mkdir -p "$marker_dir" || exit 0
mkdir "$marker_dir/$session_id" 2>/dev/null || exit 0

# shellcheck disable=SC2016 # backticks are literal Markdown
reason='PR作成前の確認: タイトルと本文が次の形になっているか見直し、直してから同じコマンドを再実行してください（この確認はこのセッションで1回だけです）。リポジトリのPRテンプレートよりこちらを優先します。

- タイトル: Conventional Commitsのtypeに続けて、目的の概要を日本語で書く（例: ci: バックエンドテストのCIログから成功テストの出力を減らす）
- 1行目: 対象Issueがあれば `close #N` で書く。親Issueに子Issueがあれば子を閉じる。PRだけでは閉じない場合は `Refs #N`、別リポジトリなら `owner/repo#N`
- 本文: 目的1文と、方針や判断した点の箇条書き2〜3個。テンプレートのセクション分けはしない
- 箇条書き: 1項目1文・1論点。前提や依存は「〜が保証する前提」のように肯定形で書く。タイトルや目的文と重複する項目は書かない
- カッコによる補足は使わない。補足が必要なら別の文にする
- IssueやPRの番号は文中に埋め込まない。GitHubがタイトルに展開し、文が読みにくくなるため。参照が必要なときは、次のように独立した行で書く
  XXXは以下で対応済み。
  → PR #11111
- 書かないもの: 「〜はやらない」「対象外」の記述、diffで分かる変更の列挙、ファイル名やクラス名などの物理名、検証手順、テストやlintの通過報告、確認チェックリスト
- 効果を測った場合だけ、変更前後の数値を短い見出し付きで添えてよい（例: ## 検証してみた）
- 日本語と英語の間にスペースを入れない'

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
