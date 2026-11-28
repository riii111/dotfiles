import json
import shlex
import sys
from pathlib import Path

path = Path(sys.argv[1])
binary = shlex.quote(sys.argv[2])
settings = {"hooks": {}}
for event, matcher, command, timeout in (
    ("PreToolUse", "^(Bash|mcp__.*)$", f"{binary} pre-tool-use --codex", 30),
    ("PermissionRequest", "^Bash$", f"{binary} permission-request", 5),
):
    settings["hooks"][event] = [
        {
            "matcher": matcher,
            "hooks": [{"type": "command", "command": command, "timeout": timeout}],
        }
    ]
path.write_text(json.dumps(settings, indent=2) + "\n")
