#!/usr/bin/env bash
# Installs the Claude Code hooks and task skills of these dotfiles into a Claude Code cloud
# environment. Set up each environment, on every account, as follows.
#
# Network access: Limited, with these allowed domains. The OpenAI ones sign the Codex CLI in;
# the rest build agent-hooks, and the CloudFront host is where download.mooncakes.io redirects,
# so a failed build whose curl cannot resolve a new host means that host moved.
#   chatgpt.com  *.chatgpt.com  auth.openai.com  api.openai.com
#   cli.moonbitlang.com  download.mooncakes.io  d251robtodj7m8.cloudfront.net
#
# Setup script. This one is downloaded before it runs, since a failed download piped into bash exits 0:
#   curl -fsSLo /tmp/cloud-setup.sh https://raw.githubusercontent.com/riii111/dotfiles/main/scripts/cloud-setup.sh && PR_LANGUAGE=ja HARNEXUS_TASK=1 bash /tmp/cloud-setup.sh
#   npm install -g @openai/codex || true
#   mkdir -p ~/.codex && printf 'forced_login_method = "chatgpt"\n' > ~/.codex/config.toml
# PR_LANGUAGE sets the PR language the PR hooks check, and HARNEXUS_TASK=1 also installs harnexus-task.
#
# Environment variables:
#   CODEX_AUTH_B64       base64 < ~/.codex/auth.json | tr -d '\n', after `codex login` on a trusted machine
#   GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL
#                        the identity the session's commits use
#
# Hooks that need local tools or chezmoi are not installed.
set -euo pipefail

dotfiles_repo=${DOTFILES_REPO:-https://github.com/riii111/dotfiles.git}
harnexus_repo=${HARNEXUS_REPO:-https://github.com/riii111/harnexus.git}
harnexus_prefix=${HARNEXUS_TASK_PREFIX:-/usr/local/bin}

script=${BASH_SOURCE[0]:-}
dotfiles=${DOTFILES_DIR:-}
if [[ -z $dotfiles && -n $script && -d $(dirname "$script")/../dot_claude/hooks ]]; then
	dotfiles=$(cd "$(dirname "$script")/.." && pwd)
fi
if [[ -z $dotfiles ]]; then
	dotfiles=$(mktemp -d)
	trap 'rm -rf "$dotfiles"' EXIT
	git clone --quiet --depth 1 "$dotfiles_repo" "$dotfiles"
fi
own="$dotfiles/scripts/cloud-setup"

hooks="$HOME/.claude/hooks"
mkdir -p "$hooks"
for name in pr-format-check pr-state-check pr-footer-reset; do
	install -m 0755 "$dotfiles/dot_claude/hooks/executable_$name.py" "$hooks/$name.py"
done
# The GitHub comment and force-push guards moved into agent-hooks. An environment cached before the move
# keeps their Python copies until a build succeeds, so a failed build never leaves the guards out.
# AGENT_HOOKS_INSTALLER replaces the build in tests, which run where the Linux toolchain does not.
guards=agent-hooks
if bash "${AGENT_HOOKS_INSTALLER:-$dotfiles/scripts/install-agent-hooks.sh}" "$hooks"; then
	rm -f "$hooks/github-comment-check.py" "$hooks/git-force-check.py"
elif [[ -x $hooks/agent-hooks ]]; then
	echo "cloud-setup: the agent-hooks build failed; the previously built agent-hooks stays" >&2
	rm -f "$hooks/github-comment-check.py" "$hooks/git-force-check.py"
elif [[ -f $hooks/github-comment-check.py && -f $hooks/git-force-check.py ]]; then
	echo "cloud-setup: the agent-hooks build failed; the previous Python guards stay" >&2
	guards=python
else
	guards=none
fi
install -m 0755 "$own/codex-auth.sh" "$hooks/codex-auth.sh"
install -m 0755 "$own/refresh.sh" "$hooks/cloud-refresh.sh"
state="$HOME/.cache/cloud-setup"
mkdir -p "$state"
{
	printf 'export HARNEXUS_TASK=%q\n' "${HARNEXUS_TASK:-}"
	printf 'export DOTFILES_REPO=%q\n' "$dotfiles_repo"
	printf 'export HARNEXUS_REPO=%q\n' "$harnexus_repo"
	printf 'export HARNEXUS_TASK_PREFIX=%q\n' "$harnexus_prefix"
} >"$state/options"
python3 "$own/claude-settings.py" "$HOME/.claude/settings.json" "$hooks" "$guards"

# The cloud harness adds attribution lines unless user instructions say otherwise; settings alone do not stop it.
cat "$dotfiles/.chezmoitemplates/agents-common.md" - >"$HOME/.claude/CLAUDE.md" <<'MD'

## Claude Code Cloud

- コミットメッセージとPR本文に、Co-Authored-By・Claude-Session・Generated with などの帰属行を付けない。
MD

# Each skill is replaced whole so a file removed upstream does not linger, and linked into
# ~/.claude/skills so Claude Code finds it by the same name.
skills="$HOME/.codex/skills"
claude_skills="$HOME/.claude/skills"
mkdir -p "$skills" "$claude_skills"
for name in ai-code-review code-review explain-change pr-watch-link task-orchestration task-review-cycle task-session-launch task-worker; do
	rm -rf "${skills:?}/$name" "${claude_skills:?}/$name"
	cp -R "$dotfiles/dot_codex/skills/$name" "$skills/$name"
	ln -s "$skills/$name" "$claude_skills/$name"
done
config="${XDG_CONFIG_HOME:-$HOME/.config}/harnexus"
mkdir -p "$config"
cat >"$config/task.json" <<JSON
{
  "templates": {
    "worker": "$skills/task-session-launch/references/worker.md",
    "reviewer": "$skills/task-review-cycle/references/reviewer.md"
  }
}
JSON

# harnexus-task needs the exact Bun harnexus pins, which the image may not have; a failed build only
# leaves it out, so the session still starts with the hooks and skills.
if [[ ${HARNEXUS_TASK:-} == 1 ]]; then
	built="$harnexus_prefix/.harnexus-task.commit"
	latest=$(git ls-remote "$harnexus_repo" HEAD 2>/dev/null | cut -f1) || latest=""
	if [[ -z $latest || ! -x $harnexus_prefix/harnexus-task || $(cat "$built" 2>/dev/null) != "$latest" ]]; then
		if ! (
			harnexus=$(mktemp -d)
			trap 'rm -rf "$harnexus"' EXIT
			# set -e does not apply inside a condition, so each step stops the rest itself.
			git clone --quiet --depth 1 "$harnexus_repo" "$harnexus" || exit 1
			bun_bin=$(command -v bun || echo "$HOME/.bun/bin/bun")
			bash "$harnexus/scripts/install-cloud-task.sh" --prefix "$harnexus_prefix" --bun "$bun_bin" || exit 1
			git -C "$harnexus" rev-parse HEAD >"$built"
		); then
			echo "cloud-setup: harnexus-task was not installed; the hooks and skills were" >&2
		fi
	fi
fi

if [[ -n ${PR_LANGUAGE:-} ]]; then
	git config --global pr.language "$PR_LANGUAGE"
fi
git config --global commit.gpgsign false
# The rest is installed first, so the session can still start; the exit status reports the missing guards.
if [[ $guards == none ]]; then
	echo "cloud-setup: the agent-hooks build failed, so the GitHub comment and force-push guards are not installed" >&2
	exit 1
fi
echo "installed the dotfiles hooks into $HOME/.claude and the task skills into $skills"
