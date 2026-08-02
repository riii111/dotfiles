#!/usr/bin/env python3

import json
import re
import shlex
import subprocess
import sys
from urllib.parse import urlparse


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


def push_urls(cwd: str) -> list[str]:
    result = subprocess.run(
        ["git", "remote", "get-url", "--push", "--all", "origin"],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def is_github_url(url: str) -> bool:
    if re.fullmatch(r"git@github\.com:[^/\s]+/[^/\s]+(?:\.git)?", url):
        return True
    parsed = urlparse(url)
    return (
        parsed.scheme in {"https", "ssh"}
        and parsed.hostname == "github.com"
        and re.fullmatch(r"/[^/\s]+/[^/\s]+(?:\.git)?", parsed.path) is not None
    )


def is_safe_auth_status(command: str) -> bool:
    try:
        return tuple(shlex.split(command)) == ("gh", "auth", "status")
    except ValueError:
        return False


def is_safe_push(command: str, cwd: str) -> bool:
    try:
        argv = shlex.split(command)
    except ValueError:
        return False

    branch = current_branch(cwd)
    if branch is None or branch in PROTECTED_BRANCHES:
        return False

    urls = push_urls(cwd)
    if not urls or not all(is_github_url(url) for url in urls):
        return False

    return tuple(argv) in {
        ("git", "push", "origin", "HEAD"),
        ("git", "push", "-u", "origin", "HEAD"),
        ("git", "push", "--set-upstream", "origin", "HEAD"),
    }


def main() -> int:
    event = json.load(sys.stdin)
    command = event.get("tool_input", {}).get("command")
    cwd = event.get("cwd")
    if not isinstance(command, str) or not isinstance(cwd, str):
        return 0
    if not is_safe_auth_status(command) and not is_safe_push(command, cwd):
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
