#!/bin/sh
set -eu

repo="${HOME}/ghq/github.com/riii111/git-prune-gone"
bin_dirs="${HOME}/bin ${HOME}/.local/bin"

[ -d "$repo" ] || exit 0

for bin_dir in $bin_dirs; do
	mkdir -p "$bin_dir"

	ln -sfn "$repo/bin/git-prune-gone" "$bin_dir/git-prune-gone"
	ln -sfn "$repo/bin/git-prune-gone-br" "$bin_dir/git-prune-gone-br"
	ln -sfn "$repo/bin/git-prune-gone-wt" "$bin_dir/git-prune-gone-wt"
done
