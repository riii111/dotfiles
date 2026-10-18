#!/usr/bin/env python3
"""Deny gh pr create/edit when the PR title or body breaks the mechanical format rules.

Rules that need judgment (restated title, mergeable bullets) belong to the prompt
hook in settings.json. A failure to parse the command never blocks it.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PR_COMMAND = re.compile(r"\bgh\s+pr\s+(create|edit)\b")
EDIT_FLAGS = re.compile(r"(--title|--body|--body-file|\s-t\s|\s-b\s|\s-F\s)")
QUOTED = r"""("(?:[^"\\]|\\.)*"|'[^']*'|[^\s"']+)"""
TITLE_FLAG = re.compile(r"(?<![\w-])(?:--title|-t)(?:\s+|=)" + QUOTED)
BODY_FLAG = re.compile(r"(?<![\w-])(?:--body|-b)(?:\s+|=)" + QUOTED)
BODY_FILE_FLAG = re.compile(r"(?<![\w-])(?:--body-file|-F)(?:\s+|=)" + QUOTED)
HEREDOC = re.compile(
    r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)^[ \t]*\2[ \t]*$", re.DOTALL | re.MULTILINE
)

TITLE_FORMAT = re.compile(
    r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(\([^)\s]+\))?!?: \S"
)
MAX_BULLETS = 3
FENCE = re.compile(r"^\s*```")
CODE_SPAN = re.compile(r"`[^`\n]*`")
LINK_TARGET = re.compile(r"\]\([^)\s]*\)")
BULLET = re.compile(r"^- (?!\[[ xX]\])")
CHECKLIST = re.compile(r"^\s*- \[[ xX]\]")
PARENTHESIS = re.compile(r"[（）()]")
REFERENCE_LINE = re.compile(
    r"^(?:(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\s+.*#\d+|→\s)", re.IGNORECASE
)
REFERENCE = re.compile(
    r"(?<![A-Za-z0-9&])(?:[\w.-]+/[\w.-]+)?#\d+\b"
    r"|https://github\.com/[^/\s]+/[^/\s]+/(?:issues|pull)/\d+"
)
JAPANESE = r"[\u3040-\u30ff\u3400-\u9fff]"
ASCII_WORD = r"[A-Za-z0-9]"
MIXED_SPACE = re.compile(rf"{JAPANESE}[ \t]+{ASCII_WORD}|{ASCII_WORD}[ \t]+{JAPANESE}")


def unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        inner = value[1:-1]
        return inner.replace('\\"', '"') if value[0] == '"' else inner
    return value


def read_title(command: str) -> str | None:
    match = TITLE_FLAG.search(command)
    return unquote(match.group(1)) if match else None


def read_body(command: str, cwd: str) -> str | None:
    heredoc = HEREDOC.search(command)
    if heredoc:
        return heredoc.group(3)
    match = BODY_FILE_FLAG.search(command)
    if match:
        path = unquote(match.group(1))
        if path == "-":
            return None
        try:
            return (Path(cwd) / path).expanduser().read_text(encoding="utf-8")
        except OSError:
            return None
    match = BODY_FLAG.search(command)
    if match and "$(" not in match.group(1):
        return unquote(match.group(1))
    return None


def prose_lines(body: str) -> list[str]:
    lines = []
    in_fence = False
    for line in body.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence:
            lines.append(LINK_TARGET.sub("]", CODE_SPAN.sub("", line)))
    return lines


def check_title(title: str) -> list[str]:
    problems = []
    if not TITLE_FORMAT.match(title):
        problems.append(
            "タイトルはConventional Commitsのtypeで始め、`type: 概要` の形にする"
        )
    if MIXED_SPACE.search(title):
        problems.append("タイトルの日本語と英語の間にスペースを入れない")
    return problems


def check_body(body: str) -> list[str]:
    lines = prose_lines(body)
    problems = []

    bullets = [line for line in lines if BULLET.match(line)]
    if len(bullets) > MAX_BULLETS:
        problems.append(
            f"箇条書きが{len(bullets)}個ある。{MAX_BULLETS}個以内に統合する"
        )
    if any(line.rstrip().endswith("。") for line in bullets):
        problems.append("箇条書きの文末に句点を付けない")
    if any(CHECKLIST.match(line) for line in lines):
        problems.append("確認チェックリストを書かない")
    if any(PARENTHESIS.search(line) for line in lines):
        problems.append("カッコによる補足を使わない。補足は別の文にする")
    if any(
        REFERENCE.search(line) and not REFERENCE_LINE.match(line.strip())
        for line in lines
    ):
        problems.append(
            "IssueやPRの番号を文中に埋め込まない。先頭の `close #N` か、"
            "独立した `→ PR #N` の行に書く"
        )
    if any(MIXED_SPACE.search(line) for line in lines):
        problems.append("本文の日本語と英語の間にスペースを入れない")
    return problems


def deny(problems: list[str]) -> None:
    reason = (
        "PRのタイトルか本文を次のとおり直し、同じコマンドを再実行してください。\n"
        + "\n".join(f"- {problem}" for problem in problems)
    )
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


def main() -> int:
    try:
        event = json.load(sys.stdin)
        command = (event.get("tool_input") or {}).get("command") or ""
        match = PR_COMMAND.search(command)
        if not match:
            return 0
        command = command[match.start() :]
        if match.group(1) == "edit" and not EDIT_FLAGS.search(command):
            return 0

        problems = []
        title = read_title(command)
        if title is not None:
            problems += check_title(title)
        body = read_body(command, event.get("cwd") or ".")
        if body is not None:
            problems += check_body(body)
        if problems:
            deny(problems)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
