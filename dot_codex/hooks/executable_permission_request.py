#!/usr/bin/env python3

"""Codex hook entry for the shared command policy."""

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

# Installed under ~/.local/share; the chezmoi source keeps it under dot_local.
_ROOT = Path(__file__).resolve().parents[2]
for _policy_dir in (
    _ROOT / ".local" / "share" / "agent-policy",
    _ROOT / "dot_local" / "share" / "agent-policy",
):
    if _policy_dir.is_dir():
        sys.path.insert(0, str(_policy_dir))
        break

from command_policy import (  # noqa: E402
    denial_reason,
    is_safe_auth_status,
    is_safe_git_permission_request,
    is_safe_push,
    segment_denial_reason,
)


def main() -> int:
    event = json.load(sys.stdin)
    command = event.get("tool_input", {}).get("command")
    cwd = event.get("cwd")
    event_name = event.get("hook_event_name")
    if not isinstance(command, str) or not isinstance(cwd, str):
        return 0
    # Paths with NUL cannot reach git, and nothing is approved for such input.
    if "\x00" in command + cwd:
        return 0
    reason = denial_reason(command, cwd) or segment_denial_reason(command, cwd)
    if reason is not None:
        if event_name == "PreToolUse":
            json.dump(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                },
                sys.stdout,
            )
            return 0
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "deny", "message": reason},
                }
            },
            sys.stdout,
        )
        return 0
    if event_name != "PermissionRequest":
        return 0
    if (
        not is_safe_auth_status(command)
        and not is_safe_git_permission_request(command, cwd)
        and not is_safe_push(command, cwd)
    ):
        return 0

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
