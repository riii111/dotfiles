#!/usr/bin/env bash
# Installs the Claude Code hooks and task skills of these dotfiles into a Claude Code cloud environment.
# Environment settings, the same on every account:
#
# Network access (Limited), allowed domains:
#   chatgpt.com
#   *.chatgpt.com
#   auth.openai.com
#   api.openai.com
#   cli.moonbitlang.com
#   download.mooncakes.io
#   d251robtodj7m8.cloudfront.net
# The last is where download.mooncakes.io redirects; if the agent-hooks build cannot resolve a new host, add it.
#
# Setup script (downloaded first, since a failed download piped into bash exits 0):
#   curl -fsSLo /tmp/cloud-setup.sh https://raw.githubusercontent.com/riii111/dotfiles/main/scripts/cloud-setup.sh && PR_LANGUAGE=ja HARNEXUS_TASK=1 bash /tmp/cloud-setup.sh
#   npm install -g @openai/codex || true
#   mkdir -p ~/.codex && printf 'forced_login_method = "chatgpt"\n' > ~/.codex/config.toml
#
# HARNEXUS_TASK=1 installs taskctl with harnexus-task linked to it, from TASKCTL_REPO at TASKCTL_REV.
# Adding TASK_CLI=legacy rolls back to the harnexus-task of HARNEXUS_REPO at HARNEXUS_REV, with taskctl linked to it.
#
# Environment variables:
#   CODEX_AUTH_B64=      output of: base64 < ~/.codex/auth.json | tr -d '\n'
#   GIT_AUTHOR_NAME=
#   GIT_AUTHOR_EMAIL=
#   GIT_COMMITTER_NAME=
#   GIT_COMMITTER_EMAIL=
set -euo pipefail

dotfiles_repo=${DOTFILES_REPO:-https://github.com/riii111/dotfiles.git}
taskctl_repo=${TASKCTL_REPO:-https://github.com/riii111/taskctl.git}
taskctl_rev=${TASKCTL_REV:-9069255654571b28bb5e2b46d48b5e3f129035fc}
# The last harnexus that builds harnexus-task, kept for rolling back; later commits drop its installer.
harnexus_repo=${HARNEXUS_REPO:-https://github.com/riii111/harnexus.git}
harnexus_rev=${HARNEXUS_REV:-8127612dfd009025c6ee95f6f3c1dba5663935ee}
task_cli=${TASK_CLI:-taskctl}
task_prefix=${HARNEXUS_TASK_PREFIX:-/usr/local/bin}

script=${BASH_SOURCE[0]:-}
dotfiles=${DOTFILES_DIR:-}
if [[ -z $dotfiles && -n $script && -f $(dirname "$script")/cloud-setup/claude-settings.py ]]; then
	dotfiles=$(cd "$(dirname "$script")/.." && pwd)
fi
state="$HOME/.cache/cloud-setup"
mkdir -p "$state"
stage=$(mktemp -d "$state/stage.XXXXXX")
cloned=
trap 'rm -rf "$stage" ${cloned:+"$cloned"}' EXIT
if [[ -z $dotfiles ]]; then
	dotfiles=$(mktemp -d)
	cloned=$dotfiles
	git clone --quiet --depth 1 "$dotfiles_repo" "$dotfiles"
fi
own="$dotfiles/scripts/cloud-setup"

hooks="$HOME/.claude/hooks"
mkdir -p "$hooks"
# The hooks moved into agent-hooks. An environment cached before a hook moved keeps its Python copy until an
# agent-hooks that has the hook is built, so a failed build never leaves a guard out.
# AGENT_HOOKS_INSTALLER replaces the build in tests, which run where the Linux toolchain does not.
if ! bash "${AGENT_HOOKS_INSTALLER:-$dotfiles/scripts/install-agent-hooks.sh}" "$hooks"; then
	echo "cloud-setup: the agent-hooks build failed; a previous agent-hooks or Python guard stays" >&2
fi
guards=()
missing=()
for name in github-comment-check git-force-check pr-format-check pr-state-check pr-footer-reset reply-reminder comment-review-check; do
	# A hook name that agent-hooks does not know makes it fail, while a known one lets an empty event through.
	if [[ -x $hooks/agent-hooks ]] && printf '{}' | "$hooks/agent-hooks" "$name" >/dev/null 2>&1; then
		guards+=("$name=agent-hooks")
		rm -f "$hooks/$name.py"
	elif [[ -f $hooks/$name.py ]]; then
		guards+=("$name=python")
	elif [[ $name != pr-footer-reset && $name != reply-reminder && $name != comment-review-check ]]; then
		# These only adjust Claude's output or advise it and guard nothing, so the setup still succeeds without them.
		missing+=("$name")
	fi
done
install -m 0755 "$own/codex-auth.sh" "$hooks/codex-auth.sh"
install -m 0755 "$own/refresh.sh" "$hooks/cloud-refresh.sh"
# The commits are kept only when given, so a refresh follows the pins of the latest dotfiles.
{
	printf 'export HARNEXUS_TASK=%q\n' "${HARNEXUS_TASK:-}"
	printf 'export TASK_CLI=%q\n' "${TASK_CLI:-}"
	printf 'export DOTFILES_REPO=%q\n' "$dotfiles_repo"
	printf 'export TASKCTL_REPO=%q\n' "$taskctl_repo"
	printf 'export TASKCTL_REV=%q\n' "${TASKCTL_REV:-}"
	printf 'export HARNEXUS_REPO=%q\n' "$harnexus_repo"
	printf 'export HARNEXUS_REV=%q\n' "${HARNEXUS_REV:-}"
	printf 'export HARNEXUS_TASK_PREFIX=%q\n' "$task_prefix"
} >"$state/options"
python3 "$own/claude-settings.py" "$HOME/.claude/settings.json" "$hooks" "${guards[@]}"

# The cloud harness adds attribution lines unless user instructions say otherwise; settings alone do not stop it.
cat "$dotfiles/.chezmoitemplates/agents-common.md" - >"$HOME/.claude/CLAUDE.md" <<'MD'

## Claude Code Cloud

- コミットメッセージとPR本文に、Co-Authored-By・Claude-Session・Generated with などの帰属行を付けない。
MD

# The skills, task.json and task CLI are switched as one set: they are prepared in $stage, and when the
# CLI cannot be built or cannot fill the staged templates, the set in place stays as it was.
skills="$HOME/.codex/skills"
claude_skills="$HOME/.claude/skills"
config="${XDG_CONFIG_HOME:-$HOME/.config}/harnexus"
task_skills=(ai-code-review code-review explain-change pr-watch-link task-orchestration task-review-cycle task-session-launch task-worker)
mkdir -p "$stage/skills" "$stage/config/harnexus"
for name in "${task_skills[@]}"; do
	cp -R "$dotfiles/dot_codex/skills/$name" "$stage/skills/$name"
done
task_json() {
	cat <<JSON
{
  "templates": {
    "worker": "$1/task-session-launch/references/worker.md",
    "reviewer": "$1/task-review-cycle/references/reviewer.md"
  }
}
JSON
}
task_json "$stage/skills" >"$stage/config/harnexus/task.json"

# The task CLI needs the exact Bun its source pins, which the image may not have.
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

install_taskctl() {
	if [[ -x $task_prefix/taskctl && ! -L $task_prefix/taskctl &&
		$(readlink "$task_prefix/harnexus-task") == taskctl &&
		$(cat "$task_prefix/.taskctl.commit" 2>/dev/null) == "$taskctl_rev" ]]; then
		XDG_CONFIG_HOME="$stage/config" "$task_prefix/taskctl" check >/dev/null
		return
	fi
	(
		source="$stage/taskctl"
		# set -e does not apply inside a condition, so each step stops the rest itself.
		fetch_commit "$source" "$taskctl_repo" "$taskctl_rev" || exit 1
		# The installer keeps one earlier harnexus-task aside and refuses to overwrite it. A harnexus-task that is
		# not its link was built by this script after that copy was made, so it is the one worth keeping.
		if [[ ! -L $task_prefix/harnexus-task ]]; then
			rm -f "$task_prefix/harnexus-task.pre-taskctl"
		fi
		# The installer checks the new binary against the templates its environment names before replacing anything.
		XDG_CONFIG_HOME="$stage/config" bash "$source/scripts/install.sh" \
			--prefix "$task_prefix" --repo "$source" --rev "$taskctl_rev" --bun "$bun_bin" --replace-harnexus-task || exit 1
		printf '%s\n' "$taskctl_rev" >"$task_prefix/.taskctl.commit"
	)
}

# The old harnexus-task has no template check, so starting it is all that is checked before the switch.
install_legacy_harnexus_task() {
	if [[ -x $task_prefix/harnexus-task && ! -L $task_prefix/harnexus-task &&
		$(cat "$task_prefix/.harnexus-task.commit" 2>/dev/null) == "$harnexus_rev" ]]; then
		"$task_prefix/harnexus-task" environment >/dev/null || return 1
	else
		(
			source="$stage/harnexus"
			built="$stage/legacy"
			fetch_commit "$source" "$harnexus_repo" "$harnexus_rev" || exit 1
			bash "$source/scripts/install-cloud-task.sh" --prefix "$built" --bun "$bun_bin" || exit 1
			"$built/harnexus-task" environment >/dev/null || exit 1
			mkdir -p "$task_prefix"
			staged=$(mktemp "$task_prefix/.harnexus-task.XXXXXX")
			install -m 0755 "$built/harnexus-task" "$staged" && mv -f "$staged" "$task_prefix/harnexus-task" || exit 1
			printf '%s\n' "$harnexus_rev" >"$task_prefix/.harnexus-task.commit"
		) || return 1
	fi
	# Skills that call taskctl reach the same binary, so one CLI writes the task state.
	link=$(mktemp -u "$task_prefix/.taskctl.XXXXXX")
	ln -s harnexus-task "$link" && mv -f "$link" "$task_prefix/taskctl"
}

switch_set=yes
if [[ ${HARNEXUS_TASK:-} == 1 ]]; then
	case $task_cli in
	taskctl) install=install_taskctl ;;
	legacy) install=install_legacy_harnexus_task ;;
	*)
		echo "cloud-setup: TASK_CLI must be taskctl or legacy, not $task_cli" >&2
		install=false
		;;
	esac
	if ! $install; then
		# Without a CLI already in place there is no set to keep, and the hooks still need the skills.
		if [[ -x $task_prefix/harnexus-task || -x $task_prefix/taskctl ]] && [[ -d $skills/task-worker ]]; then
			switch_set=no
			echo "cloud-setup: the $task_cli set was not installed; the previous skills, task.json and task CLI stay" >&2
		else
			echo "cloud-setup: the $task_cli set was not installed; the hooks and skills were" >&2
		fi
	fi
fi

# Each skill is replaced whole so a file removed upstream does not linger, and linked into
# ~/.claude/skills so Claude Code finds it by the same name.
if [[ $switch_set == yes ]]; then
	mkdir -p "$skills" "$claude_skills" "$config"
	for name in "${task_skills[@]}"; do
		rm -rf "${skills:?}/$name" "${claude_skills:?}/$name"
		mv "$stage/skills/$name" "$skills/$name"
		ln -s "$skills/$name" "$claude_skills/$name"
	done
	task_json "$skills" >"$config/task.json"
fi

if [[ -n ${PR_LANGUAGE:-} ]]; then
	git config --global pr.language "$PR_LANGUAGE"
fi
git config --global commit.gpgsign false
# The rest is installed first, so the session can still start; the exit status reports the missing guards.
if ((${#missing[@]})); then
	echo "cloud-setup: the agent-hooks build failed, so these guards are not installed: ${missing[*]}" >&2
	exit 1
fi
echo "installed the dotfiles hooks into $HOME/.claude and the task skills into $skills"
