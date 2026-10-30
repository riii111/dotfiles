#!/usr/bin/env bash
# Installs the Claude Code hooks of these dotfiles into a Claude Code cloud environment,
# whose user settings start empty and which chezmoi does not manage.
#
# Add to the environment's setup script; it is downloaded first, since a failed download piped
# into bash would exit 0 and start the session without the hooks:
#   curl -fsSLo /tmp/cloud-setup.sh https://raw.githubusercontent.com/riii111/dotfiles/main/scripts/cloud-setup.sh && PR_LANGUAGE=ja bash /tmp/cloud-setup.sh
#
# PR_LANGUAGE sets the global `git config pr.language` the PR format hook requires, since a fresh
# clone has none. Running it again replaces the hooks it installed and keeps other settings.
# Left out: the inline Bash hook, which steers find, grep and cat to fd, rg and bat that a cloud
# VM lacks, and with them loses its terraform and publish guards, which need credentials a cloud
# VM rarely holds; the prompt hooks, which need chezmoi templates and see only gh, while cloud
# sessions use GitHub MCP; and the hooks that only log or set up local worktrees.
set -euo pipefail

script=${BASH_SOURCE[0]:-}
dotfiles=${DOTFILES_DIR:-}
if [[ -z $dotfiles && -n $script && -d $(dirname "$script")/../dot_claude/hooks ]]; then
  dotfiles=$(cd "$(dirname "$script")/.." && pwd)
fi
if [[ -z $dotfiles ]]; then
  dotfiles=$(mktemp -d)
  trap 'rm -rf "$dotfiles"' EXIT
  git clone --quiet --depth 1 "${DOTFILES_REPO:-https://github.com/riii111/dotfiles.git}" "$dotfiles"
fi

hooks="$HOME/.claude/hooks"
mkdir -p "$hooks"
for name in github-comment-check git-force-check pr-format-check pr-state-check; do
  install -m 0755 "$dotfiles/dot_claude/hooks/executable_$name.py" "$hooks/$name.py"
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
# Only the commands this script installs are taken out before they are added again, so another
# hook, even one in the same folder or group, stays; a group left with no hooks goes.
installed = {hook["command"] for group in ours for hook in group["hooks"]}
for group in groups:
    group["hooks"] = [
        hook for hook in group.get("hooks", []) if hook.get("command") not in installed
    ]
groups[:] = [group for group in groups if group["hooks"]]
groups.extend(ours)
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
PY

if [[ -n ${PR_LANGUAGE:-} ]]; then
  git config --global pr.language "$PR_LANGUAGE"
fi
echo "installed the dotfiles hooks into $HOME/.claude"
