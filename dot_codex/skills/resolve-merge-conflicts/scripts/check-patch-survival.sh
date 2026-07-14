#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'Usage: %s --base <rev> --tip <rev> [--head <rev>] [--nonexact-only] [--fail-on-nonexact]\n' "$0"
}

base=''
tip=''
head='HEAD'
strict=0
nonexact_only=0

while (($#)); do
	case "$1" in
	--base)
		base=${2:?}
		shift 2
		;;
	--tip)
		tip=${2:?}
		shift 2
		;;
	--head)
		head=${2:?}
		shift 2
		;;
	--fail-on-nonexact)
		strict=1
		shift
		;;
	--nonexact-only)
		nonexact_only=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 64
		;;
	esac
done

[[ -n "$base" && -n "$tip" ]] || {
	usage >&2
	exit 64
}
for rev in "$base" "$tip" "$head"; do
	git rev-parse --verify -q "${rev}^{commit}" >/dev/null || {
		printf 'Invalid revision: %s\n' "$rev" >&2
		exit 64
	}
done

patch=$(mktemp "${TMPDIR:-/tmp}/check-patch-survival.XXXXXX")
index=$(mktemp "${TMPDIR:-/tmp}/check-patch-survival-index.XXXXXX")
rm -f "$index"
trap 'rm -f "$patch" "$index"' EXIT
GIT_INDEX_FILE="$index" git read-tree "$head"

exact=0
absent=0
adapted=0
total=0

while IFS= read -r -d '' path; do
	total=$((total + 1))
	git diff --binary "$base" "$tip" -- "$path" >"$patch"

	if GIT_INDEX_FILE="$index" git apply --cached --reverse --check "$patch" >/dev/null 2>&1; then
		if ((!nonexact_only)); then
			printf 'exact\t%s\n' "$path"
		fi
		exact=$((exact + 1))
	elif GIT_INDEX_FILE="$index" git apply --cached --check "$patch" >/dev/null 2>&1; then
		printf 'absent\t%s\n' "$path"
		absent=$((absent + 1))
	else
		printf 'adapted-or-partial\t%s\n' "$path"
		adapted=$((adapted + 1))
	fi
done < <(git diff --name-only -z "$base" "$tip")

printf 'summary\ttotal=%d\texact=%d\tabsent=%d\tadapted-or-partial=%d\n' \
	"$total" "$exact" "$absent" "$adapted"

if ((strict && (absent || adapted))); then
	exit 2
fi
