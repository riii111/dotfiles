import json
import os
import re
import sys
from pathlib import Path

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


# Every hook an earlier run may have installed, Python or agent-hooks, is taken out before this run adds its own.
names = (
    "pre-tool-use",
    "github-comment-check",
    "git-force-check",
    "pr-format-check",
    "pr-state-check",
    "comment-review-check",
    "pr-footer-reset",
    "reply-reminder",
)
retired = {f"python3 {hooks}/{name}.py" for name in names} | {
    f"{hooks}/agent-hooks {name}" for name in names
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
if guards.get("pre-tool-use") == "agent-hooks":
    # One process runs every check on the tools its own hook matched, as in the local settings. No
    # --steer-tools: the cloud image has neither fd nor bat. The safety rules run without a flag.
    ours = [{"matcher": "^(Bash|mcp__.*)$", "hooks": guard("pre-tool-use", 30)}]
else:
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
                *guard("comment-review-check", 10),
            ],
        },
    ]
ours = [group for group in ours if group["hooks"]]
# Not in the local settings on purpose: only the GitHub MCP server of cloud sessions appends a footer to a new PR.
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


def local_permissions():
    template = Path(__file__).resolve().parents[2] / "dot_claude" / "settings.json.tmpl"
    text = template.read_text()
    block = re.search(r'^  "permissions": (\{.*?^  \})', text, re.S | re.M).group(1)
    # Rules that name local paths through chezmoi variables have no counterpart in the cloud container, so they are dropped rather than rendered.
    lines = [line for line in block.splitlines() if "{{" not in line]
    rules = json.loads(re.sub(r",(\s*[\]}])", r"\1", "\n".join(lines)))
    # The cloud harness exposes claude.ai connectors without the claude_ai_ prefix, so local rules are renamed to match there.
    return {
        kind: [rule.replace("mcp__claude_ai_", "mcp__") for rule in rules.get(kind, [])]
        for kind in ("allow", "deny", "ask")
    }


permissions = settings.setdefault("permissions", {})
# A narrow allow rule is decided before the auto mode classifier, which refused lease pushes.
extra = {"allow": ["Bash(git push --force-with-lease *)"]}
for kind, rules in local_permissions().items():
    current = permissions.setdefault(kind, [])
    for rule in [*rules, *extra.get(kind, [])]:
        if rule not in current:
            current.append(rule)
settings["attribution"] = False
settings["includeCoAuthoredBy"] = False
with open(path, "w") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
