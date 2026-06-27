#!/bin/sh
set -eu

repo="${HOME}/ghq/github.com/riii111/git-prune-gone"
install_root="${HOME}/.local"

[ -d "$repo" ] || exit 0
command -v cargo >/dev/null 2>&1 || exit 0

if command -v rustup >/dev/null 2>&1 && rustup toolchain list | grep -q '^1\.96\.0-'; then
	rustup run 1.96.0 cargo install --path "$repo" --root "$install_root" --locked --force
else
	cargo install --path "$repo" --root "$install_root" --locked --force
fi

mkdir -p "${HOME}/bin"
ln -sfn "${install_root}/bin/git-prune-gone" "${HOME}/bin/git-prune-gone"

cat >"${install_root}/bin/git-prune-gone-br" <<'EOF'
#!/bin/sh
exec git-prune-gone branch "$@"
EOF
chmod +x "${install_root}/bin/git-prune-gone-br"

cat >"${install_root}/bin/git-prune-gone-wt" <<'EOF'
#!/bin/sh
exec git-prune-gone worktree "$@"
EOF
chmod +x "${install_root}/bin/git-prune-gone-wt"

ln -sfn "${install_root}/bin/git-prune-gone-br" "${HOME}/bin/git-prune-gone-br"
ln -sfn "${install_root}/bin/git-prune-gone-wt" "${HOME}/bin/git-prune-gone-wt"
