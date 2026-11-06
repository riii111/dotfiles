import json
import os
import sys

path, hooks = sys.argv[1], sys.argv[2]
# Each hook comes as NAME=agent-hooks or NAME=python; a hook left out is not installed.
guards = dict(arg.split("=", 1) for arg in sys.argv[3:])


def command(name, timeout=5):
    return {
        "type": "command",
        "command": f"python3 {hooks}/{name}.py",
        "timeout": timeout,
    }


def guard(name, timeout=5):
    if guards.get(name) == "python":
        return [command(name, timeout)]
    if guards.get(name) == "agent-hooks":
        return [
            {
                "type": "command",
                "command": f"{hooks}/agent-hooks {name}",
                "timeout": timeout,
            }
        ]
    return []


# The Python hooks, taken out of settings written before the move unless they are kept.
retired = {
    f"python3 {hooks}/{name}.py"
    for name in (
        "github-comment-check",
        "git-force-check",
        "pr-format-check",
        "pr-state-check",
        "pr-footer-reset",
    )
}

start = [
    {
        "hooks": [
            {
                "type": "command",
                "command": f"bash {hooks}/codex-auth.sh",
                "timeout": 10,
            },
            {
                "type": "command",
                "command": f"bash {hooks}/cloud-refresh.sh",
                "timeout": 10,
            },
        ]
    }
]
ours = [
    {"matcher": "^(Bash|mcp__.*)$", "hooks": guard("github-comment-check")},
    {
        "matcher": "^mcp__github__.*$",
        "hooks": [*guard("pr-format-check"), *guard("pr-state-check")],
    },
    {
        "matcher": "Bash",
        "hooks": [
            *guard("git-force-check"),
            *guard("pr-format-check"),
            *guard("pr-state-check", 15),
        ],
    },
]
ours = [group for group in ours if group["hooks"]]
after = [
    {
        "matcher": "^mcp__github__create_pull_request$",
        "hooks": guard("pr-footer-reset"),
    },
]
after = [group for group in after if group["hooks"]]
prompt = [{"hooks": guard("reply-reminder")}]
prompt = [group for group in prompt if group["hooks"]]

settings = {}
if os.path.exists(path):
    with open(path) as file:
        settings = json.load(file)
# Only the commands cloud-setup.sh installs are taken out before they are added again,
# so another hook, even one in the same folder or group, stays; a group left with no
# hooks goes.
for event, added in (
    ("PreToolUse", ours),
    ("PostToolUse", after),
    ("UserPromptSubmit", prompt),
    ("SessionStart", start),
):
    groups = settings.setdefault("hooks", {}).setdefault(event, [])
    installed = retired | {
        hook["command"] for group in added for hook in group["hooks"]
    }
    for group in groups:
        group["hooks"] = [
            hook
            for hook in group.get("hooks", [])
            if hook.get("command") not in installed
        ]
    groups[:] = [group for group in groups if group["hooks"]]
    groups.extend(added)
# A narrow allow rule is decided before the auto mode classifier, which refused lease pushes.
allow = settings.setdefault("permissions", {}).setdefault("allow", [])
for rule in ("Bash(git push --force-with-lease *)",):
    if rule not in allow:
        allow.append(rule)
settings["attribution"] = False
settings["includeCoAuthoredBy"] = False
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
