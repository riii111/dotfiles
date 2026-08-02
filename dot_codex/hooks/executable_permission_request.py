#!/usr/bin/env python3

import json
import shlex
import subprocess
import sys


PROTECTED_BRANCHES = {"main", "master"}


def current_branch(cwd: str) -> str | None:
    result = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def git_config(cwd: str, key: str) -> str | None:
    result = subprocess.run(
        ["git", "config", "--get", key],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def is_safe_push(command: str, cwd: str) -> bool:
    try:
        argv = shlex.split(command)
    except ValueError:
        return False

    branch = current_branch(cwd)
    if branch is None or branch in PROTECTED_BRANCHES:
        return False

    safe_commands = {
        ("git", "push", "origin", "HEAD"),
        ("git", "push", "origin", branch),
        ("git", "push", "-u", "origin", "HEAD"),
        ("git", "push", "-u", "origin", branch),
        ("git", "push", "--set-upstream", "origin", "HEAD"),
        ("git", "push", "--set-upstream", "origin", branch),
    }
    if git_config(cwd, f"branch.{branch}.remote") == "origin" and git_config(
        cwd, f"branch.{branch}.merge"
    ) == f"refs/heads/{branch}":
        safe_commands.add(("git", "push"))
    return tuple(argv) in safe_commands


def main() -> int:
    event = json.load(sys.stdin)
    command = event.get("tool_input", {}).get("command")
    cwd = event.get("cwd")
    if not isinstance(command, str) or not isinstance(cwd, str):
        return 0
    if not is_safe_push(command, cwd):
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
