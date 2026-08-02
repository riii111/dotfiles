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


def origin_urls(cwd: str, *, push: bool) -> list[str]:
    args = ["git", "remote", "get-url"]
    if push:
        args.append("--push")
    args.extend(["--all", "origin"])
    result = subprocess.run(
        args,
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


def is_safe_git_read(command: str, cwd: str) -> bool:
    try:
        argv = tuple(shlex.split(command))
    except ValueError:
        return False

    if argv == ("git", "branch", "--show-current"):
        return True
    if argv != ("git", "fetch", "origin"):
        return False

    urls = origin_urls(cwd, push=False)
    return bool(urls) and all(is_github_url(url) for url in urls)


def denial_reason(command: str) -> str | None:
    try:
        argv = shlex.split(command)
    except ValueError:
        return None

    for index in range(len(argv) - 2):
        if argv[index : index + 3] == ["gh", "auth", "status"]:
            segment = argv[index + 3 :]
            if any(
                arg == "--show-token"
                or (arg.startswith("-") and not arg.startswith("--") and "t" in arg[1:])
                for arg in segment
            ):
                return "GitHub access-token output is forbidden."

    for index in range(len(argv) - 1):
        if argv[index : index + 2] == ["git", "reset"]:
            segment = argv[index + 2 :]
            if "--hard" in segment:
                return "Hard reset is forbidden."

    return None


def is_safe_push(command: str, cwd: str) -> bool:
    try:
        argv = shlex.split(command)
    except ValueError:
        return False

    branch = current_branch(cwd)
    if branch is None or branch in PROTECTED_BRANCHES:
        return False

    urls = origin_urls(cwd, push=True)
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
    reason = denial_reason(command)
    if reason is not None:
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
    if (
        not is_safe_auth_status(command)
        and not is_safe_git_read(command, cwd)
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
