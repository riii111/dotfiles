#!/usr/bin/env bash

set -euo pipefail

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
inspect="$skill_dir/scripts/inspect.sh"
if [ ! -f "$inspect" ]; then
	inspect="$skill_dir/scripts/executable_inspect.sh"
fi
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/macos-storage-triage-test.XXXXXX")"
mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"
trap 'rm -rf "$tmpdir"' EXIT

assert_row() {
	local file="$1"
	local kind="$2"
	local status="$3"
	local path="$4"
	if awk -F '\t' -v kind="$kind" -v status="$status" -v path="$path" '
		$1 == kind && $2 == status && $3 == path { found = 1 }
		END { exit !found }
	' "$file"; then
		return
	fi
	cat "$file" >&2
	return 1
}

cat >"$mock_bin/pgrep" <<'EOF'
#!/usr/bin/env bash
case "${PROCESS_MODE:-none}" in
none) exit 1 ;;
failure | match) printf '4242 rustc\n' ;;
esac
EOF

cat >"$mock_bin/lsof" <<'EOF'
#!/usr/bin/env bash
case "${PROCESS_MODE:-none}" in
failure) printf 'cwd unavailable\n' >&2; exit 1 ;;
match) printf 'p4242\nfcwd\nn%s\n' "$PROCESS_CWD" ;;
esac
EOF

cat >"$mock_bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'n%.0s' {1..1700}
printf '\n'
printf 'warning from nix\n' >&2
EOF

cat >"$mock_bin/nix-collect-garbage" <<'EOF'
#!/usr/bin/env bash
printf 'g%.0s' {1..1700}
printf '\n'
EOF

cat >"$mock_bin/du" <<'EOF'
#!/usr/bin/env bash
path="${!#}"
if [ "${MOCK_DU_MODE:-}" = partial ] && [[ "$path" == *blocked ]]; then
	printf 'permission denied\n' >&2
	exit 1
fi
printf '1\t%s\n' "$path"
EOF

cat >"$mock_bin/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = --cache ]; then
	printf '%s\n' "$HOME/Library/Caches/Homebrew"
fi
EOF

cat >"$mock_bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$mock_bin/rustup" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$mock_bin/sccache" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$mock_bin"/*

create_worktree() {
	local path="$1"
	mkdir -p "$path/target"
	touch "$path/Cargo.toml"
	git -C "$path" init -q
}

run_inspect() {
	local home="$1"
	local output="$2"
	shift 2
	PATH="$mock_bin:$PATH" \
		HOME="$home" \
		PROCESS_MODE="${PROCESS_MODE:-none}" \
		PROCESS_CWD="${PROCESS_CWD:-}" \
		MOCK_DU_MODE="${MOCK_DU_MODE:-}" \
		bash "$inspect" "$@" >"$output"
}

home="$tmpdir/home"
mkdir -p "$home"
repo="$tmpdir/repo"
create_worktree "$repo"
repo="$(cd "$repo" && pwd -P)"

long_output="$tmpdir/long.tsv"
run_inspect "$home" "$long_output" --with-nix-dry-run "$repo"
grep -Fq '[truncated: 1701 bytes total; tail:' "$long_output"
grep -Fq '[stderr:' "$long_output"

failure_output="$tmpdir/failure.tsv"
PROCESS_MODE=failure run_inspect "$home" "$failure_output" "$repo"
assert_row "$failure_output" rust_target running_hold "$repo/target"

other_repo="$tmpdir/other-repo"
create_worktree "$other_repo"
other_repo="$(cd "$other_repo" && pwd -P)"
matched_output="$tmpdir/matched.tsv"
PROCESS_MODE=match PROCESS_CWD="$repo" run_inspect "$home" "$matched_output" "$repo" "$other_repo"
assert_row "$matched_output" rust_target running_hold "$repo/target"
assert_row "$matched_output" rust_target rebuildable_needs_confirmation "$other_repo/target"

mkdir -p "$home/Library/Application Support/ok"
mkdir -p "$home/Library/Application Support/blocked"
partial_output="$tmpdir/partial.tsv"
MOCK_DU_MODE=partial run_inspect "$home" "$partial_output" --with-deep-sizes "$repo"
assert_row "$partial_output" app_support_child unverified "$home/Library/Application Support/blocked"
assert_row "$partial_output" app_support unverified "$home/Library/Application Support"

printf 'inspect tests passed\n'
