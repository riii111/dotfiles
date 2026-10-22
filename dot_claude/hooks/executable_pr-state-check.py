#!/usr/bin/env python3
"""Protect review approvals; uncertain PR identity must not authorize a mutation."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


VALUE_FLAGS = {
    "-R",
    "--repo",
    "-B",
    "--base",
    "-b",
    "--body",
    "-F",
    "--body-file",
    "-t",
    "--title",
    "-m",
    "--milestone",
    "--add-label",
    "--remove-label",
    "--add-assignee",
    "--remove-assignee",
    "--add-reviewer",
    "--remove-reviewer",
    "--add-project",
    "--remove-project",
    "--attach",
}


def segments(command: str) -> list[list[str]]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    result: list[list[str]] = [[]]
    for token in lexer:
        if token and all(char in ";&|()\n" for char in token):
            result.append([])
        else:
            result[-1].append(token)
    return [part for part in result if part]


def query_args(args: list[str]) -> tuple[list[str], bool]:
    repo, targets = [], []
    dangerous = False
    index = 0
    while index < len(args):
        arg = args[index]
        flag = arg.split("=", 1)[0]
        if flag in {"--undo", "--base", "-B"} or arg.startswith("-B"):
            dangerous = True
        if flag in VALUE_FLAGS:
            value = arg.split("=", 1)[1] if "=" in arg else args[index + 1]
            if "=" not in arg:
                index += 1
            if flag in {"-R", "--repo"}:
                repo = ["--repo", value]
        elif arg.startswith("-R"):
            repo = ["--repo", arg[2:]]
        elif not arg.startswith("-"):
            targets.append(arg)
        index += 1
    if len(targets) > 1 or any(re.search(r"[$`]", item) for item in repo + targets):
        raise ValueError("PR identity is dynamic or ambiguous")
    return [*targets, *repo], dangerous


def check(command: str, cwd: str) -> str | None:
    if not re.search(r"\bgh\b.*\bpr\b.*\b(?:ready|edit)\b", command, re.DOTALL):
        return None
    try:
        deadline = time.monotonic() + 10
        for part in segments(command):
            if part[0] == "cd":
                if len(part) != 2 or re.search(r"[$`~]", part[1]):
                    raise ValueError("working directory is dynamic")
                cwd = str(Path(cwd, part[1]).resolve())
                continue
            environment = os.environ.copy()
            while part and (
                re.match(r"\w+=", part[0]) or part[0] in {"env", "command"}
            ):
                if "=" in part[0]:
                    key, value = part[0].split("=", 1)
                    if re.search(r"[$`]", value):
                        raise ValueError("environment is dynamic")
                    environment[key] = value
                part = part[1:]
            if not part or Path(part[0]).name != "gh":
                continue
            args = part[1:]
            prefix = []
            if args and args[0] in {"-R", "--repo"}:
                prefix, args = args[:2], args[2:]
            elif args and (args[0].startswith("--repo=") or args[0].startswith("-R")):
                prefix, args = args[:1], args[1:]
            if len(args) < 2 or args[0] != "pr" or args[1] not in {"edit", "ready"}:
                continue
            if "--help" in args or "-h" in args:
                continue
            query, dangerous = query_args(prefix + args[2:])
            if not dangerous:
                continue
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("lookup deadline exceeded")
            result = subprocess.run(
                [part[0], "pr", "view", *query, "--json", "isDraft"],
                cwd=cwd,
                env=environment,
                capture_output=True,
                text=True,
                timeout=min(5, remaining),
                check=True,
            )
            if json.loads(result.stdout).get("isDraft") is not True:
                return "Open済みPRのDraft化・base変更は禁止。承認を保つため操作を止めました。"
    except (
        ValueError,
        TypeError,
        AttributeError,
        IndexError,
        OSError,
        subprocess.SubprocessError,
    ):
        return "PRがDraftか確認できないため操作を止めました。対象PR・リポジトリ・接続を確認してください。"
    return None


def main() -> int:
    event = json.load(sys.stdin)
    reason = check(
        (event.get("tool_input") or {}).get("command") or "",
        event.get("cwd") or os.getcwd(),
    )
    if reason:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
