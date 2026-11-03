import json
import os
import sys

path, hooks, guards = sys.argv[1], sys.argv[2], sys.argv[3]


def command(name, timeout=5):
    return {
        "type": "command",
        "command": f"python3 {hooks}/{name}.py",
        "timeout": timeout,
    }


def guard(name):
    if guards == "python":
        return [command(name)]
    if guards == "agent-hooks":
        return [
            {"type": "command", "command": f"{hooks}/agent-hooks {name}", "timeout": 5}
        ]
    return []


# The Python guards, taken out of settings written before the move unless they are kept.
retired = {
    f"python3 {hooks}/github-comment-check.py",
    f"python3 {hooks}/git-force-check.py",
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
        "hooks": [command("pr-format-check"), command("pr-state-check")],
    },
    {
        "matcher": "Bash",
        "hooks": [
            *guard("git-force-check"),
            command("pr-format-check"),
            command("pr-state-check", 15),
        ],
    },
]
ours = [group for group in ours if group["hooks"]]
after = [
    {
        "matcher": "^mcp__github__create_pull_request$",
        "hooks": [command("pr-footer-reset")],
    },
]

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
settings["attribution"] = False
settings["includeCoAuthoredBy"] = False
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
