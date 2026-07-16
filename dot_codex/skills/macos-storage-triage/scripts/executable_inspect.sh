#!/usr/bin/env bash

set -u
set -o pipefail

printf 'kind\tstatus\tpath\tbytes\tdetail\n'

include_nix_dry_run=false
include_deep_sizes=false
roots=()
if ! tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/macos-storage-triage.XXXXXX")"; then
	exit 1
fi
worktree_roots="$tmpdir/worktree-roots"
process_cwds="$tmpdir/process-cwds"
process_scan_state=clear
: >"$worktree_roots"
: >"$process_cwds"

cleanup() {
	rm -rf "$tmpdir"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

new_temp() {
	mktemp "$tmpdir/file.XXXXXX"
}

for argument in "$@"; do
	if [ "$argument" = '--with-nix-dry-run' ]; then
		include_nix_dry_run=true
	elif [ "$argument" = '--with-deep-sizes' ]; then
		include_deep_sizes=true
	else
		roots+=("$argument")
	fi
done

compact() {
	tr '\t\r\n' ' '
}

summarize_file() {
	local file="$1"
	local bytes head tail
	bytes="$(wc -c <"$file" | tr -d ' ')"
	if [ "$bytes" -le 1500 ]; then
		compact <"$file"
		return
	fi
	head="$(head -c 1000 "$file" | compact)"
	tail="$(tail -c 500 "$file" | compact)"
	printf '%s [truncated: %s bytes total; tail: %s]' "$head" "$bytes" "$tail"
}

emit() {
	printf '%s\t%s\t%s\t%s\t%s\n' \
		"$(printf '%s' "$1" | compact)" \
		"$(printf '%s' "$2" | compact)" \
		"$(printf '%s' "$3" | compact)" \
		"$(printf '%s' "$4" | compact)" \
		"$(printf '%s' "$5" | compact)"
}

run_command() {
	local kind="$1"
	shift
	local output error status detail
	output="$(new_temp)"
	error="$(new_temp)"
	if "$@" >"$output" 2>"$error"; then
		detail="$(summarize_file "$output")"
		if [ -s "$error" ]; then
			detail="$detail [stderr: $(summarize_file "$error")]"
		fi
		emit "$kind" observed '' '' "$detail"
	else
		status=$?
		detail="$(summarize_file "$error")"
		emit "$kind" unverified '' '' "exit $status: $detail"
	fi
	rm -f "$output" "$error"
}

measure() {
	local kind="$1"
	local status="$2"
	local path="$3"
	local context="${4:-}"
	local output error stat_error kilobytes modified detail
	if [ ! -e "$path" ]; then
		emit "$kind" absent "$path" '' ''
		return
	fi
	output="$(new_temp)"
	error="$(new_temp)"
	stat_error="$(new_temp)"
	if du -sk "$path" >"$output" 2>"$error"; then
		kilobytes="$(awk 'NR == 1 { print $1 }' "$output")"
		if modified="$(stat -f '%m' "$path" 2>"$stat_error")"; then
			detail="$context"
			if [ -n "$detail" ]; then
				detail="$detail; "
			fi
			detail="${detail}directory_mtime_epoch=$modified"
		else
			detail="$context"
			if [ -n "$detail" ]; then
				detail="$detail; "
			fi
			detail="${detail}directory mtime unavailable: $(summarize_file "$stat_error")"
		fi
		if [ -s "$error" ]; then
			detail="$detail [stderr: $(summarize_file "$error")]"
		fi
		emit "$kind" "$status" "$path" "$((kilobytes * 1024))" "$detail"
	else
		detail="$(summarize_file "$error")"
		emit "$kind" unverified "$path" '' "$detail"
	fi
	rm -f "$output" "$error" "$stat_error"
}

measure_children() {
	local kind="$1"
	local status="$2"
	local path="$3"
	local child output error kilobytes total=0 measured=0 unresolved=0 detail
	if [ ! -d "$path" ]; then
		emit "$kind" absent "$path" '' ''
		return
	fi
	for child in "$path"/* "$path"/.[!.]*; do
		[ -e "$child" ] || continue
		output="$(new_temp)"
		error="$(new_temp)"
		if du -sk "$child" >"$output" 2>"$error"; then
			kilobytes="$(awk 'NR == 1 { print $1 }' "$output")"
			total=$((total + kilobytes * 1024))
			measured=$((measured + 1))
			emit "${kind}_child" "$status" "$child" "$((kilobytes * 1024))" ''
		else
			unresolved=$((unresolved + 1))
			detail="$(summarize_file "$error")"
			emit "${kind}_child" unverified "$child" '' "$detail"
		fi
		rm -f "$output" "$error"
	done
	if [ "$unresolved" -gt 0 ]; then
		status=unverified
	fi
	emit "$kind" "$status" "$path" "$total" "direct children measured=$measured; unverified=$unresolved"
}

command_or_unverified() {
	local command="$1"
	local kind="$2"
	if command -v "$command" >/dev/null 2>&1; then
		shift 2
		run_command "$kind" "$@"
	else
		emit "$kind" unverified '' '' "$command is not installed"
	fi
}

collect_rust_processes() {
	local output error line pid cwd detail scan_status
	if ! command -v pgrep >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
		process_scan_state=unverified
		emit rust_processes unverified '' '' 'pgrep or lsof is not installed'
		return
	fi
	output="$(new_temp)"
	error="$(new_temp)"
	if pgrep -l '^(rust-analyzer|cargo|rustc|sccache)$' >"$output" 2>"$error"; then
		while IFS= read -r line; do
			pid="${line%% *}"
			if lsof -a -p "$pid" -d cwd -Fn >"$error" 2>&1; then
				cwd="$(sed -n 's/^n//p' "$error")"
				if [ -n "$cwd" ]; then
					printf '%s\t%s\n' "$pid" "$cwd" >>"$process_cwds"
					emit rust_process running_hold "$cwd" '' "pid=$pid; $line"
				else
					process_scan_state=unverified
					emit rust_process unverified '' '' "pid=$pid has no cwd"
				fi
			else
				process_scan_state=unverified
				detail="$(summarize_file "$error")"
				emit rust_process unverified '' '' "pid=$pid: $detail"
			fi
		done <"$output"
	else
		scan_status=$?
		if [ "$scan_status" -eq 1 ]; then
			emit rust_processes observed '' '' 'no matching processes'
		else
			process_scan_state=unverified
			detail="$(summarize_file "$error")"
			emit rust_processes unverified '' '' "exit $scan_status: $detail"
		fi
	fi
	rm -f "$output" "$error"
}

target_status() {
	local project="$1"
	local pid cwd
	if [ "$process_scan_state" = unverified ]; then
		printf '%s' running_hold
		return
	fi
	while IFS=$'\t' read -r pid cwd; do
		case "$cwd" in
		"$project" | "$project"/*)
			printf '%s' running_hold
			return
			;;
		esac
	done <"$process_cwds"
	printf '%s' rebuildable_needs_confirmation
}

inspect_worktree() {
	local root="$1"
	local manifest project toolchain output error detail git_error target_state
	if [ ! -d "$root" ]; then
		emit rust_worktree unverified "$root" '' 'directory does not exist'
		return
	fi
	output="$(new_temp)"
	error="$(new_temp)"
	if fd -a -t f '^Cargo\.toml$' "$root" --hidden --no-ignore --exclude .git >"$output" 2>"$error"; then
		while IFS= read -r manifest; do
			git_error="$(new_temp)"
			if project="$(git -C "$(dirname "$manifest")" rev-parse --show-toplevel 2>"$git_error")"; then
				rm -f "$git_error"
			else
				detail="$(summarize_file "$git_error")"
				rm -f "$git_error"
				emit rust_worktree unverified "${manifest%/Cargo.toml}" '' "Git worktree root unavailable: $detail"
				continue
			fi
			if grep -Fqx "$project" "$worktree_roots"; then
				continue
			fi
			printf '%s\n' "$project" >>"$worktree_roots"
			target_state="$(target_status "$project")"
			emit rust_worktree observed "$project" '' "target_status=$target_state"
			measure rust_target "$target_state" "$project/target"
			measure rust_target "$target_state" "$project/.nvim/target"
			for toolchain in "$project/rust-toolchain" "$project/rust-toolchain.toml"; do
				if [ -f "$toolchain" ]; then
					emit rust_toolchain_config observed "$toolchain" '' ''
				fi
			done
		done <"$output"
	else
		detail="$(summarize_file "$error")"
		emit rust_worktree unverified "$root" '' "$detail"
	fi
	rm -f "$output" "$error"
}

collect_rust_processes

if command -v fd >/dev/null 2>&1; then
	for root in "${roots[@]}"; do
		inspect_worktree "$root"
	done
	if [ "${#roots[@]}" -eq 0 ]; then
		inspect_worktree "$PWD"
	fi
else
	emit rust_worktree unverified '' '' 'fd is not installed'
fi

run_command filesystem_root df -k /
run_command filesystem_data df -k /System/Volumes/Data
if [ "$include_deep_sizes" = true ]; then
	measure nix_store rebuildable_needs_confirmation /nix/store
	measure rustup rebuildable_needs_confirmation "$HOME/.rustup"
	measure cargo_registry rebuildable_needs_confirmation "$HOME/.cargo/registry"
	measure_children app_support persistent_hold "$HOME/Library/Application Support"
	measure_children cache rebuildable_needs_confirmation "$HOME/Library/Caches"
else
	emit nix_store unverified /nix/store '' 'not run: pass --with-deep-sizes'
	emit rustup unverified "$HOME/.rustup" '' 'not run: pass --with-deep-sizes'
	emit cargo_registry unverified "$HOME/.cargo/registry" '' 'not run: pass --with-deep-sizes'
	emit app_support unverified "$HOME/Library/Application Support" '' 'not run: pass --with-deep-sizes'
	emit cache unverified "$HOME/Library/Caches" '' 'not run: pass --with-deep-sizes'
fi

command_or_unverified rustup rustup_toolchains rustup toolchain list
command_or_unverified rustup rustup_overrides rustup override list
command_or_unverified rustup rustup_active rustup show active-toolchain
command_or_unverified sccache sccache_stats sccache --show-stats
if [ "$include_nix_dry_run" = true ]; then
	command_or_unverified nix nix_generation_dry_run nix-collect-garbage --delete-older-than 30d --dry-run
	command_or_unverified nix nix_store_gc_dry_run nix store gc --dry-run
else
	emit nix_generation_dry_run unverified '' '' 'not run: pass --with-nix-dry-run'
	emit nix_store_gc_dry_run unverified '' '' 'not run: pass --with-nix-dry-run'
fi
emit nix_system_generation_dry_run unverified '' '' 'not run: requires explicit sudo'
command_or_unverified docker docker_system_df docker system df
command_or_unverified docker docker_containers docker ps --format '{{.Names}}\t{{.Status}}'

if command -v brew >/dev/null 2>&1; then
	brew_output="$(new_temp)"
	brew_error="$(new_temp)"
	if brew --cache >"$brew_output" 2>"$brew_error"; then
		brew_cache="$(cat "$brew_output")"
		brew_detail=''
		if [ -s "$brew_error" ]; then
			brew_detail="brew --cache stderr: $(summarize_file "$brew_error")"
		fi
		if [ "$include_deep_sizes" = true ]; then
			measure homebrew_cache rebuildable_needs_confirmation "$brew_cache" "$brew_detail"
		else
			if [ -n "$brew_detail" ]; then
				brew_detail=" [$brew_detail]"
			fi
			emit homebrew_cache unverified "$brew_cache" '' "not run: pass --with-deep-sizes$brew_detail"
		fi
	else
		emit homebrew_cache unverified '' '' "$(summarize_file "$brew_error")"
	fi
	rm -f "$brew_output" "$brew_error"
	run_command homebrew_cleanup_dry_run brew cleanup --dry-run
	run_command homebrew_autoremove_dry_run brew autoremove --dry-run
else
	emit homebrew unverified '' '' 'brew is not installed'
fi
