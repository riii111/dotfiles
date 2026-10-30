#!/usr/bin/env bash
# Installs the Claude Code hooks of these dotfiles into a Claude Code cloud environment,
# whose user settings start empty and which chezmoi does not manage.
#
# Add to the environment's setup script:
#   curl -fsSL https://raw.githubusercontent.com/riii111/dotfiles/main/scripts/cloud-setup.sh | PR_LANGUAGE=ja bash
#
# PR_LANGUAGE sets the global `git config pr.language` the PR format hook requires, since a fresh
# clone has none. The hooks that need tools a cloud VM lacks (fd, bat) or that only log locally
# are left out. Running it again replaces the hooks it installed and keeps other settings.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)
source=${DOTFILES_DIR:-}
if [[ -z $source && -d $here/../dot_claude/hooks ]]; then
  source=$(cd "$here/.." && pwd)
fi
if [[ -z $source ]]; then
  source=$(mktemp -d)
  trap 'rm -rf "$source"' EXIT
  git clone --quiet --depth 1 "${DOTFILES_REPO:-https://github.com/riii111/dotfiles.git}" "$source"
fi

hooks="$HOME/.claude/hooks"
mkdir -p "$hooks"
for name in github-comment-check git-force-check pr-format-check pr-state-check; do
  install -m 0755 "$source/dot_claude/hooks/executable_$name.py" "$hooks/$name.py"
done

python3 - "$HOME/.claude/settings.json" "$hooks" <<'PY'
import json
import os
import sys

path, hooks = sys.argv[1], sys.argv[2]


def command(name, timeout=5):
    return {"type": "command", "command": f"python3 {hooks}/{name}.py", "timeout": timeout}


ours = [
    {"matcher": "^(Bash|mcp__.*)$", "hooks": [command("github-comment-check")]},
    {
        "matcher": "^mcp__github__.*$",
        "hooks": [command("pr-format-check"), command("pr-state-check")],
    },
    {
        "matcher": "Bash",
        "hooks": [
            command("git-force-check"),
            command("pr-format-check"),
            command("pr-state-check", 15),
        ],
    },
]

settings = {}
if os.path.exists(path):
    with open(path) as file:
        settings = json.load(file)
groups = settings.setdefault("hooks", {}).setdefault("PreToolUse", [])
# Groups this script installed earlier are replaced, so running it again adds nothing twice.
groups[:] = [
    group
    for group in groups
    if not any(hooks in hook.get("command", "") for hook in group.get("hooks", []))
]
groups.extend(ours)
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
PY

if [[ -n ${PR_LANGUAGE:-} ]]; then
  git config --global pr.language "$PR_LANGUAGE"
fi
echo "installed the dotfiles hooks into $HOME/.claude"
