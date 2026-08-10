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

if [ "${GH_TEST_FAILURE:-}" = 1 ]; then
  printf 'simulated gh failure\n' >&2
  exit 23
fi

if [ "$1 $2" = "repo view" ]; then
  printf '{"nameWithOwner":"riii111/dotfiles"}\n'
  exit 0
fi

if [ "$1 $2" = "pr checks" ]; then
  printf '[{"name":"ci","state":"SUCCESS","bucket":"pass","link":"https://example.test/ci"}]\n'
  exit 0
fi

if [ "$1 $2" = "api graphql" ]; then
  payload="$(cat)"
  if [ "${GH_TEST_MISSING_PR:-}" = 1 ]; then
    printf '{"data":{"repository":{"pullRequest":null}}}\n'
    exit 0
  fi
  if jq -e '.query | contains("reviewThreads")' <<<"$payload" >/dev/null; then
    if jq -e '.variables.cursor == "thread-cursor"' <<<"$payload" >/dev/null; then
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"number":42,"url":"https://github.com/riii111/dotfiles/pull/42","title":"Test","state":"OPEN","isDraft":false,"headRefOid":"head","baseRefOid":"base","reviewThreads":{"nodes":[{"id":"thread-resolved","isResolved":true,"isOutdated":false,"path":"b.rs","line":2,"originalLine":2,"startLine":null,"diffSide":"RIGHT","resolvedBy":{"login":"author"},"comments":{"nodes":[],"pageInfo":{"hasNextPage":true,"endCursor":"resolved-comment-cursor"}}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
    else
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"number":42,"url":"https://github.com/riii111/dotfiles/pull/42","title":"Test","state":"OPEN","isDraft":false,"headRefOid":"head","baseRefOid":"base","reviewThreads":{"nodes":[{"id":"thread-unresolved","isResolved":false,"isOutdated":false,"path":"a.rs","line":10,"originalLine":9,"startLine":null,"diffSide":"RIGHT","resolvedBy":null,"comments":{"nodes":[{"id":"comment-1","databaseId":1,"url":"https://example.test/1","body":"fix this","author":{"login":"reviewer"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","path":"a.rs","line":10,"originalLine":9,"diffHunk":"@@","replyTo":null}],"pageInfo":{"hasNextPage":true,"endCursor":"comment-cursor"}}}],"pageInfo":{"hasNextPage":true,"endCursor":"thread-cursor"}}}}}}
JSON
    fi
    exit 0
  fi
  if jq -e '.query | contains("PullRequestReviewThread")' <<<"$payload" >/dev/null; then
    if jq -e '.variables.id == "thread-resolved"' <<<"$payload" >/dev/null; then
      if [ "${GH_FAIL_RESOLVED_COMMENTS:-}" = 1 ]; then
        printf 'resolved comments should not be fetched\n' >&2
        exit 88
      fi
      cat <<'JSON'
{"data":{"node":{"comments":{"nodes":[{"id":"comment-resolved","databaseId":6,"url":"https://example.test/6","body":"resolved follow-up","author":{"login":"author"},"createdAt":"2026-01-03T00:00:00Z","updatedAt":"2026-01-03T00:00:00Z","path":"b.rs","line":2,"originalLine":2,"diffHunk":"@@","replyTo":null}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
      exit 0
    fi
    cat <<'JSON'
{"data":{"node":{"comments":{"nodes":[{"id":"comment-2","databaseId":2,"url":"https://example.test/2","body":"follow-up","author":{"login":"author"},"createdAt":"2026-01-02T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","path":"a.rs","line":10,"originalLine":9,"diffHunk":"@@","replyTo":{"id":"comment-1"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
    exit 0
  fi
fi

if [ "$1" = api ] && [[ "$*" == *issues/42/comments* ]]; then
  if [ "${GH_TEST_PAGINATION_FAILURE:-}" = 1 ]; then
    printf 'simulated pagination failure\n' >&2
    exit 31
  fi
  printf '[[{"id":2,"body":"conversation"}],[{"id":4,"body":"conversation page 2"}]]\n'
  exit 0
fi

if [ "$1" = api ] && [[ "$*" == *repos/riii111/dotfiles/issues/42* ]]; then
  if [ "${GH_TEST_MISSING_ISSUE:-}" = 1 ]; then
    printf 'missing issue\n' >&2
    exit 44
  fi
  printf '{"number":42,"title":"Issue","state":"open","body":"body"}\n'
  exit 0
fi

if [ "$1" = api ] && [[ "$*" == *pulls/42/reviews* ]]; then
  printf '[[{"id":3,"state":"CHANGES_REQUESTED"}],[{"id":5,"state":"COMMENTED"}]]\n'
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$tmpdir/bin/gh"

output="$tmpdir/output.json"
GH_FAIL_RESOLVED_COMMENTS=1 PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 >"$output"
jq -e '
  .pullRequest.number == 42 and
  .checks[0].name == "ci" and
  .conversationComments[0].body == "conversation" and
  .conversationComments[1].body == "conversation page 2" and
  .reviews[0].state == "CHANGES_REQUESTED" and
  .reviews[1].state == "COMMENTED" and
  (.reviewThreads | length) == 1 and
  .reviewThreads[0].id == "thread-unresolved" and
  (.reviewThreads[0].comments | length) == 2 and
  .reviewThreads[0].comments[1].body == "follow-up" and
  .includesResolvedThreads == false
' "$output" >/dev/null

PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 --include-resolved >"$output"
jq -e '
  (.reviewThreads | length) == 2 and
  .includesResolvedThreads == true and
  .reviewThreads[1].comments[0].body == "resolved follow-up"
' "$output" >/dev/null

PATH="$tmpdir/bin:$PATH" python3 "$wrapper" https://github.com/riii111/dotfiles/pull/42 >"$output"
jq -e '.pullRequest.number == 42' "$output" >/dev/null

PATH="$tmpdir/bin:$PATH" python3 "$repo_root/bin/executable_gh-read" issue 42 >"$output"
jq -e '.issue.number == 42 and .comments[1].body == "conversation page 2"' "$output" >/dev/null
PATH="$tmpdir/bin:$PATH" python3 "$repo_root/bin/executable_gh-read" issue https://github.com/riii111/dotfiles/issues/42 --compact >"$output"
jq -e '.issue.number == 42' "$output" >/dev/null

PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 --compact >"$output"
jq -e '.reviewThreads[0].comments[0] | has("diffHunk") | not' "$output" >/dev/null
test "$(wc -l <"$output")" -eq 1

if PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 0 >"$output" 2>/dev/null; then
	printf 'invalid PR number unexpectedly succeeded\n' >&2
	exit 1
fi

expect_failure() {
	if PATH="$tmpdir/bin:$PATH" python3 "$wrapper" "$@" >"$output" 2>/dev/null; then
		printf 'invalid arguments unexpectedly succeeded: %s\n' "$*" >&2
		exit 1
	fi
}

expect_failure '²'
expect_failure 42 --repo ../..
expect_failure https://github.com/riii111/dotfiles/pull/42 --repo other/repo
expect_failure https://github.com/riii111/dotfiles/issues/42 --repo other/repo

set +e
GH_TEST_FAILURE=1 PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 >"$output" 2>"$tmpdir/error"
status=$?
set -e
test "$status" -eq 23
grep -q 'simulated gh failure' "$tmpdir/error"

set +e
GH_TEST_MISSING_PR=1 PATH="$tmpdir/bin:$PATH" python3 "$wrapper" 42 >"$output" 2>"$tmpdir/error"
status=$?
set -e
test "$status" -eq 1
grep -q 'pull request not found: riii111/dotfiles#42' "$tmpdir/error"

set +e
GH_TEST_MISSING_ISSUE=1 PATH="$tmpdir/bin:$PATH" python3 "$repo_root/bin/executable_gh-read" issue 42 >"$output" 2>"$tmpdir/error"
status=$?
set -e
test "$status" -eq 44
grep -q 'missing issue' "$tmpdir/error"

set +e
GH_TEST_PAGINATION_FAILURE=1 PATH="$tmpdir/bin:$PATH" python3 "$repo_root/bin/executable_gh-read" pr 42 >"$output" 2>"$tmpdir/error"
status=$?
set -e
test "$status" -eq 31
grep -q 'simulated pagination failure' "$tmpdir/error"

printf 'gh-pr-comments tests passed\n'
