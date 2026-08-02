#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wrapper="$repo_root/bin/executable_gh-pr-comments"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/gh-pr-comments-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1 $2" = "repo view" ]; then
  printf 'riii111/dotfiles\n'
  exit 0
fi

if [ "$1 $2" = "api graphql" ]; then
  payload="$(cat)"
  if jq -e '.query | contains("reviewThreads")' <<<"$payload" >/dev/null; then
    cat <<'JSON'
{"data":{"repository":{"pullRequest":{"number":42,"url":"https://github.com/riii111/dotfiles/pull/42","title":"Test","state":"OPEN","isDraft":false,"headRefOid":"head","baseRefOid":"base","reviewThreads":{"nodes":[{"id":"thread-unresolved","isResolved":false,"isOutdated":false,"path":"a.rs","line":10,"originalLine":9,"startLine":null,"diffSide":"RIGHT","resolvedBy":null,"comments":{"nodes":[{"id":"comment-1","databaseId":1,"url":"https://example.test/1","body":"fix this","author":{"login":"reviewer"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","path":"a.rs","line":10,"originalLine":9,"diffHunk":"@@","replyTo":null}],"pageInfo":{"hasNextPage":false,"endCursor":null}}},{"id":"thread-resolved","isResolved":true,"isOutdated":false,"path":"b.rs","line":2,"originalLine":2,"startLine":null,"diffSide":"RIGHT","resolvedBy":{"login":"author"},"comments":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
    exit 0
  fi
fi

if [ "$1" = api ] && [[ "$*" == *issues/42/comments* ]]; then
  printf '[[{"id":2,"body":"conversation"}]]\n'
  exit 0
fi

if [ "$1" = api ] && [[ "$*" == *pulls/42/reviews* ]]; then
  printf '[[{"id":3,"state":"CHANGES_REQUESTED"}]]\n'
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$tmpdir/bin/gh"

output="$tmpdir/output.json"
PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 >"$output"
jq -e '
  .pullRequest.number == 42 and
  .conversationComments[0].body == "conversation" and
  .reviews[0].state == "CHANGES_REQUESTED" and
  (.reviewThreads | length) == 1 and
  .reviewThreads[0].id == "thread-unresolved" and
  .includesResolvedThreads == false
' "$output" >/dev/null

PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 --include-resolved >"$output"
jq -e '(.reviewThreads | length) == 2 and .includesResolvedThreads == true' "$output" >/dev/null

if PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 0 >"$output" 2>/dev/null; then
	printf 'invalid PR number unexpectedly succeeded\n' >&2
	exit 1
fi

printf 'gh-pr-comments tests passed\n'
