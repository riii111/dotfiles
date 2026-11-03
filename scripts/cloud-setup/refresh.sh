#!/usr/bin/env bash
# The environment caches what cloud-setup.sh installed for days, so each session start runs it again
# from the latest dotfiles, with the options it was given.
state="$HOME/.cache/cloud-setup"

refresh() {
	# flock belongs to the open file, which the setup's children inherit, so the lock lasts while any
	# of them still writes and ends however they exit. One refresh runs at a time; another skips.
	exec 9>"$state/refresh.flock" || return 0
	python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)' 2>/dev/null || return 0
	# Left by the directory lock of earlier versions.
	rm -rf "$state/refresh.lock" "$state/refresh.lock.reap"
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
