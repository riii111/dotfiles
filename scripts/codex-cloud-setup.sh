#!/usr/bin/env bash
# Run in a fresh Codex Cloud environment with a dotfiles checkout and the target repository.
set -euo pipefail

dotfiles=${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
project=${1:?usage: codex-cloud-setup.sh PROJECT_DIRECTORY}
project=$(cd "$project" && pwd)
own="$dotfiles/scripts/cloud-setup"
skills="$project/.agents/skills"
config="${XDG_CONFIG_HOME:-$HOME/.config}/harnexus"
hooks="$HOME/.local/share/dotfiles-cloud/hooks"
task_prefix=${HARNEXUS_CREW_PREFIX:-$HOME/.local/bin}
# shellcheck disable=SC2034 # Used by crew.sh.
crew_repo=${HARNEXUS_CREW_REPO:-https://github.com/riii111/taskctl.git}
# shellcheck disable=SC2034 # Used by crew.sh.
crew_rev=${HARNEXUS_CREW_REV:-670be108d6013552e22dda54ffe9236a89c27cc3}
stage=$(mktemp -d)
names=()
while IFS= read -r name; do
	[[ -n $name ]] && names+=("$name")
done <"$own/skills.list"
for name in "${names[@]}"; do
	if [[ -e $skills/$name || -L $skills/$name ]]; then
		echo "codex-cloud-setup: $skills/$name already exists" >&2
		exit 1
	fi
done
if [[ -e $hooks/agent-hooks ]]; then
	echo "codex-cloud-setup: $hooks/agent-hooks already exists" >&2
	exit 1
fi
if [[ -e $task_prefix/harnexus-crew ]] && [[ $(cat "$task_prefix/.harnexus-crew.commit" 2>/dev/null) != "$crew_rev" ]]; then
	echo "codex-cloud-setup: $task_prefix/harnexus-crew already exists with a different or unknown revision" >&2
	exit 1
fi
if [[ -e $config/task.json || -e $HOME/.codex/hooks.json || -e $HOME/.codex/AGENTS.md ]]; then
	echo 'codex-cloud-setup: task.json, hooks.json or AGENTS.md already exists' >&2
	exit 1
fi
mkdir -p "$stage/skills" "$stage/config/harnexus" "$stage/hooks" "$task_prefix"
for name in "${names[@]}"; do
	cp -R "$dotfiles/dot_codex/skills/$name" "$stage/skills/$name"
done
task_json() {
	python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

skills = Path(sys.argv[1])
print(json.dumps({"templates": {
    "worker": str(skills / "task-session-launch/references/worker.md"),
    "reviewer": str(skills / "task-review-cycle/references/reviewer.md"),
}}, indent=2))
PY
}
task_json "$stage/skills" >"$stage/config/harnexus/task.json"
# shellcheck source=/dev/null
. "$own/crew.sh"
install_crew
bash "${AGENT_HOOKS_INSTALLER:-$dotfiles/scripts/install-agent-hooks.sh}" "$stage/hooks"
for name in pre-tool-use permission-request; do
	printf '{}' | "$stage/hooks/agent-hooks" "$name" >/dev/null
done
mkdir -p "$skills" "$config" "$hooks" "$HOME/.codex"
for name in "${names[@]}"; do
	mv "$stage/skills/$name" "$skills/$name"
done
install -m 0755 "$stage/hooks/agent-hooks" "$hooks/agent-hooks"
task_json "$skills" >"$config/task.json"
cp "$dotfiles/.chezmoitemplates/agents-common.md" "$HOME/.codex/AGENTS.md"
python3 "$own/codex-settings.py" "$HOME/.codex/hooks.json" "$hooks/agent-hooks"
revision=$(git -C "$dotfiles" rev-parse HEAD)
if [[ -n $(git -C "$dotfiles" status --porcelain) ]]; then revision+=-dirty; fi
printf 'dotfiles: %s\nharnexus-crew: %s\nskills: %s\n' "$revision" "$crew_rev" "$skills"
