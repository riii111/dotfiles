#!/usr/bin/env bash
# Installs the Claude Code hooks of these dotfiles into a Claude Code cloud environment,
# whose user settings start empty and which chezmoi does not manage.
#
# Add to the environment's setup script; it is downloaded first, since a failed download piped
# into bash would exit 0 and start the session without the hooks:
#   curl -fsSLo /tmp/cloud-setup.sh https://raw.githubusercontent.com/riii111/dotfiles/main/scripts/cloud-setup.sh && PR_LANGUAGE=ja bash /tmp/cloud-setup.sh
#
# It also places the task review skills where the Codex CLI and harnexus-task read them, so a
# worker can review with `harnexus-task review` there; HARNEXUS_TASK=1 builds harnexus-task too.
#
# Each session start runs it again in the background from the latest dotfiles, so skills, hooks and
# harnexus-task follow main without waiting for the environment's cache to be rebuilt.
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
# The environment's variables are set only once Claude Code starts, after this script, so the Codex
# login the environment holds in CODEX_AUTH_B64 is written by a session start hook. It prints nothing.
cat > "$hooks/codex-auth.sh" <<'SH'
#!/usr/bin/env bash
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
[[ -s $auth || -z ${CODEX_AUTH_B64:-} ]] && exit 0
mkdir -p "$(dirname "$auth")"
umask 077
written=$(mktemp "$auth.XXXXXX") || exit 0
if printf %s "$CODEX_AUTH_B64" | base64 -d > "$written" 2>/dev/null; then
  mv -f "$written" "$auth"
else
  rm -f "$written"
fi
exit 0
SH
chmod 0755 "$hooks/codex-auth.sh"
# The environment caches what this script installed for days, so each session start runs it again
# from the latest dotfiles in the background, with the options it was given; nothing is printed.
state="$HOME/.cache/cloud-setup"
mkdir -p "$state"
{
  printf 'export HARNEXUS_TASK=%q\n' "${HARNEXUS_TASK:-}"
  printf 'export DOTFILES_REPO=%q\n' "${DOTFILES_REPO:-https://github.com/riii111/dotfiles.git}"
  printf 'export HARNEXUS_REPO=%q\n' "${HARNEXUS_REPO:-https://github.com/riii111/harnexus.git}"
  printf 'export HARNEXUS_TASK_PREFIX=%q\n' "${HARNEXUS_TASK_PREFIX:-/usr/local/bin}"
} > "$state/options"
cat > "$hooks/cloud-refresh.sh" <<'SH'
#!/usr/bin/env bash
state="$HOME/.cache/cloud-setup"
# One refresh runs at a time, however long it takes; a lock whose holder has died is taken over.
refresh() {
  lock="$state/refresh.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    holder=$(cat "$lock/pid" 2>/dev/null)
    if [[ -z $holder ]] || kill -0 "$holder" 2>/dev/null; then
      return 0
    fi
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || return 0
  fi
  echo "${BASHPID:-$$}" > "$lock/pid"
  # shellcheck source=/dev/null
  . "$state/options"
  dotfiles=$(mktemp -d)
  if git clone --quiet --depth 1 "$DOTFILES_REPO" "$dotfiles"; then
    DOTFILES_DIR="$dotfiles" bash "$dotfiles/scripts/cloud-setup.sh"
  fi
  rm -rf "$dotfiles" "$lock"
}
if [[ ${CLOUD_REFRESH_FOREGROUND:-} == 1 ]]; then
  refresh
else
  refresh > "$state/refresh.log" 2>&1 < /dev/null &
  disown
fi
exit 0
SH
chmod 0755 "$hooks/cloud-refresh.sh"

python3 - "$HOME/.claude/settings.json" "$hooks" <<'PY'
import json
import os
import sys

path, hooks = sys.argv[1], sys.argv[2]


def command(name, timeout=5):
    return {"type": "command", "command": f"python3 {hooks}/{name}.py", "timeout": timeout}


start = [
    {
        "hooks": [
            {"type": "command", "command": f"bash {hooks}/codex-auth.sh", "timeout": 10},
            {"type": "command", "command": f"bash {hooks}/cloud-refresh.sh", "timeout": 10},
        ]
    }
]
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
# Only the commands this script installs are taken out before they are added again, so another
# hook, even one in the same folder or group, stays; a group left with no hooks goes.
for event, added in (("PreToolUse", ours), ("SessionStart", start)):
    groups = settings.setdefault("hooks", {}).setdefault(event, [])
    installed = {hook["command"] for group in added for hook in group["hooks"]}
    for group in groups:
        group["hooks"] = [
            hook for hook in group.get("hooks", []) if hook.get("command") not in installed
        ]
    groups[:] = [group for group in groups if group["hooks"]]
    groups.extend(added)
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
PY

# The skills the review cycle reads, replaced whole so a file removed upstream does not linger.
skills="$HOME/.codex/skills"
mkdir -p "$skills"
# Claude Code finds the same skills by name through ~/.claude/skills, so a request can name one.
claude_skills="$HOME/.claude/skills"
mkdir -p "$claude_skills"
for name in ai-code-review code-review explain-change pr-watch-link task-orchestration task-review-cycle task-session-launch task-worker; do
  rm -rf "${skills:?}/$name" "${claude_skills:?}/$name"
  cp -R "$dotfiles/dot_codex/skills/$name" "$skills/$name"
  ln -s "$skills/$name" "$claude_skills/$name"
done
config="${XDG_CONFIG_HOME:-$HOME/.config}/harnexus"
mkdir -p "$config"
cat > "$config/task.json" <<JSON
{
  "templates": {
    "worker": "$skills/task-session-launch/references/worker.md",
    "reviewer": "$skills/task-review-cycle/references/reviewer.md"
  }
}
JSON

# harnexus-task needs the exact Bun harnexus pins, which the image may not have; a failed build only
# leaves it out, so the session still starts with the hooks.
# A harnexus-task built from the commit the repository's default branch points at now is kept, so a
# session start rebuilds it only after harnexus changed.
built="${HARNEXUS_TASK_PREFIX:-/usr/local/bin}/.harnexus-task.commit"
latest=""
if [[ ${HARNEXUS_TASK:-} == 1 ]]; then
  latest=$(git ls-remote "${HARNEXUS_REPO:-https://github.com/riii111/harnexus.git}" HEAD 2>/dev/null | cut -f1) || latest=""
fi
if [[ ${HARNEXUS_TASK:-} == 1 && -n $latest && -x ${HARNEXUS_TASK_PREFIX:-/usr/local/bin}/harnexus-task && $(cat "$built" 2>/dev/null) == "$latest" ]]; then
  :
elif [[ ${HARNEXUS_TASK:-} == 1 ]]; then
  if ! (
    harnexus=$(mktemp -d)
    trap 'rm -rf "$harnexus"' EXIT
    # set -e does not apply inside a condition, so each step stops the rest itself.
    git clone --quiet --depth 1 "${HARNEXUS_REPO:-https://github.com/riii111/harnexus.git}" "$harnexus" || exit 1
    bun_bin=$(command -v bun || echo "$HOME/.bun/bin/bun")
    bash "$harnexus/scripts/install-cloud-task.sh" --prefix "${HARNEXUS_TASK_PREFIX:-/usr/local/bin}" --bun "$bun_bin" || exit 1
    git -C "$harnexus" rev-parse HEAD > "$built"
  ); then
    echo "cloud-setup: harnexus-task was not installed; the hooks and skills were" >&2
  fi
fi

if [[ -n ${PR_LANGUAGE:-} ]]; then
  git config --global pr.language "$PR_LANGUAGE"
fi
echo "installed the dotfiles hooks into $HOME/.claude and the task skills into $skills"
