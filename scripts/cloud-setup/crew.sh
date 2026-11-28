# shellcheck shell=bash
# shellcheck disable=SC2154 # The caller supplies the installation paths and revision.
# Older CLI revisions use Bun; current revisions use MoonBit or Nix.
bun_bin=$(command -v bun || echo "$HOME/.bun/bin/bun")

# Fetches one commit only, so the source built is the commit asked for.
fetch_commit() {
	[[ $3 =~ ^[0-9a-f]{40}$ ]] || {
		echo "cloud-setup: $3 is not a full commit SHA" >&2
		return 1
	}
	git init --quiet "$1" &&
		git -C "$1" fetch --quiet --depth 1 "$2" "$3" &&
		git -C "$1" checkout --quiet --detach FETCH_HEAD &&
		[[ $(git -C "$1" rev-parse HEAD) == "$3" ]]
}

install_crew() {
	if [[ -x $task_prefix/harnexus-crew &&
		$(cat "$task_prefix/.harnexus-crew.commit" 2>/dev/null) == "$crew_rev" ]]; then
		XDG_CONFIG_HOME="$stage/config" "$task_prefix/harnexus-crew" check >/dev/null
		return
	fi
	(
		source="$stage/harnexus-crew"
		fetch_commit "$source" "$crew_repo" "$crew_rev" || exit 1
		if [[ ${HARNEXUS_CREW_TOOLCHAIN:-moon} == moon ]]; then
			bash "${HARNEXUS_CREW_MOON_INSTALLER:-$own/crew-moon.sh}" "$stage/moon" || exit 1
			export MOON_TOOLCHAIN_ROOT="$stage/moon/toolchain"
			export PATH="$MOON_TOOLCHAIN_ROOT/bin:$PATH"
			XDG_CONFIG_HOME="$stage/config" bash "$source/scripts/install.sh" \
				--prefix "$task_prefix" --repo "$source" --rev "$crew_rev" --moon "$MOON_TOOLCHAIN_ROOT/bin/moon" || exit 1
		elif [[ $HARNEXUS_CREW_TOOLCHAIN == bun ]]; then
			XDG_CONFIG_HOME="$stage/config" bash "$source/scripts/install.sh" \
				--prefix "$task_prefix" --repo "$source" --rev "$crew_rev" --bun "$bun_bin" || exit 1
		else
			echo "cloud-setup: HARNEXUS_CREW_TOOLCHAIN must be moon or bun" >&2
			exit 1
		fi
		printf '%s\n' "$crew_rev" >"$task_prefix/.harnexus-crew.commit"
	)
}
