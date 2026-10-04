#!/usr/bin/env python3
"""Record permission prompts and auto mode denials for sandbox-review.

The hook never returns a decision, so the prompt or denial goes on unchanged.
"""

import json
import sys
import time
from pathlib import Path

LOG = Path.home() / ".local" / "state" / "claude" / "permission-events.jsonl"
MAX_COMMAND = 500


def main() -> int:
    try:
        event = json.load(sys.stdin)
        record = {
            "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "event": event.get("hook_event_name"),
            "session": event.get("session_id"),
            "cwd": event.get("cwd"),
            "mode": event.get("permission_mode"),
            "tool": event.get("tool_name"),
        }
        tool_input = event.get("tool_input") or {}
        if event.get("tool_name") == "Bash":
            record["command"] = str(tool_input.get("command", ""))[:MAX_COMMAND]
            record["unsandboxed"] = bool(tool_input.get("dangerouslyDisableSandbox"))
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as log:
            log.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        # A logging failure must never change the permission flow.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
