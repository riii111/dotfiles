#!/usr/bin/env python3

"""Claude Code PreToolUse hook for the shared command policy."""

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from command_policy import (  # noqa: E402
    approves_outside_sandbox,
    denial_reason,
    push_needs_approval,
    segment_denial_reason,
)


def main() -> int:
    event = json.load(sys.stdin)
    tool_input = event.get("tool_input", {})
    command = tool_input.get("command")
    cwd = event.get("cwd")
    if not isinstance(command, str) or not isinstance(cwd, str):
        return 0
    if "\x00" in command + cwd:
        return respond(
            {
                "permissionDecision": "ask",
                "permissionDecisionReason": "The command contains a NUL character.",
            }
        )
    if not Path(cwd).is_dir():
        return 0
    # Claude Code asks where Codex refuses, so a person can still approve the command.
    reason = denial_reason(command, cwd) or segment_denial_reason(command, cwd)
    if reason is None and push_needs_approval(command, cwd):
        reason = "This push may run on a protected branch or with hidden options."
    if reason is not None:
        return respond(
            {"permissionDecision": "ask", "permissionDecisionReason": reason}
        )
    if approves_outside_sandbox(command, cwd):
        return respond(
            {
                "permissionDecision": "allow",
                "permissionDecisionReason": "Allowed by the shared command policy.",
                "updatedInput": {**tool_input, "dangerouslyDisableSandbox": True},
            }
        )
    return 0


def respond(decision: dict) -> int:
    json.dump(
        {"hookSpecificOutput": {"hookEventName": "PreToolUse", **decision}},
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
