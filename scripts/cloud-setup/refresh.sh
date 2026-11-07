#!/usr/bin/env bash
# The environment caches what cloud-setup.sh installed for days, so each session start runs it again
# from the latest dotfiles, with the options it was given.
state="$HOME/.cache/cloud-setup"

refresh() {
	# flock belongs to the open file, which the setup's children inherit, so the lock lasts while any
	# of them still writes and ends however they exit. One refresh runs at a time; another skips.
	exec 9>"$state/refresh.flock" || return 0
	# util-linux flock is on every Ubuntu image, and starts faster than Python.
	flock -n 9 || return 0
	# A refresh from before flock may still be writing under its directory lock during the upgrade.
	# It writes its pid right after taking the lock, so the lock is left over only once that pid
	# has died, or when none was written within a minute.
	legacy="$state/refresh.lock"
	if [[ -d $legacy ]]; then
		holder=$(cat "$legacy/pid" 2>/dev/null)
		if [[ -n $holder ]] && kill -0 "$holder" 2>/dev/null; then
			return 0
		fi
		if [[ -z $holder && -z $(find "$legacy" -maxdepth 0 -mmin +1) ]]; then
			return 0
		fi
		rm -rf "$legacy" "$legacy.reap"
	fi
	# shellcheck source=/dev/null
	. "$state/options"
	checkout="$state/dotfiles"
	if [[ -d $checkout/.git && $(git -C "$checkout" remote get-url origin 2>/dev/null) == "$DOTFILES_REPO" ]]; then
		git -C "$checkout" fetch --quiet --depth 1 origin HEAD &&
			git -C "$checkout" reset --quiet --hard FETCH_HEAD &&
			git -C "$checkout" clean -qffdx || return 0
	else
		rm -rf "$checkout"
		if ! git clone --quiet --depth 1 "$DOTFILES_REPO" "$checkout"; then
			rm -rf "$checkout"
			return 0
		fi
	fi
	DOTFILES_DIR="$checkout" bash "$checkout/scripts/cloud-setup.sh"
}

if [[ ${CLOUD_REFRESH_FOREGROUND:-} == 1 ]]; then
	refresh
else
	refresh >"$state/refresh.log" 2>&1 </dev/null &
	disown
fi
exit 0
