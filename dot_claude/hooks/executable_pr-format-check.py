#!/usr/bin/env python3
"""Deny gh pr create/edit when the PR title or body breaks the mechanical format rules.

Rules that need judgment (restated title, mergeable bullets) belong to the prompt
hook in settings.json, which only sees the command text. The body therefore has to be
written inside the command, as a heredoc or a literal. An exception while parsing the
command never blocks it.

The language comes from `git config pr.language` (ja or en) in the session's working
directory. It is set per repository by the user, so an unset value blocks the PR
instead of being guessed.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

PR_COMMAND = re.compile(r"\bgh\s+pr\s+(create|edit)\b")
EDIT_FLAGS = re.compile(r"(--title|--body|--body-file|\s-t\s|\s-b\s|\s-F\s)")
QUOTED = r"""("(?:[^"\\]|\\.)*"|'[^']*'|[^\s"']+)"""
TITLE_FLAG = re.compile(r"(?<![\w-])(?:--title|-t)(?:\s+|=)" + QUOTED)
BODY_FLAG = re.compile(r"(?<![\w-])(?:--body|-b)(?:\s+|=)" + QUOTED)
BODY_FILE_FLAG = re.compile(r"(?<![\w-])(?:--body-file|-F)(?:\s+|=)" + QUOTED)
HEREDOC = re.compile(
    r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)^[ \t]*\2[ \t]*$", re.DOTALL | re.MULTILINE
)
DYNAMIC_VALUE = re.compile(r"\$[\w{(]|`")

TITLE_FORMAT = re.compile(
    r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(\([^)\s]+\))?!?: \S"
)
MAX_BULLETS = 3
FENCE = re.compile(r"^\s*```")
CODE_SPAN = re.compile(r"`[^`\n]*`")
LINK_TARGET = re.compile(r"\]\([^)\s]*\)")
LIST_MARKER = r"(?:[-*+]|\d+[.)])"
TOP_LEVEL_BULLET = re.compile(rf"^ {{0,3}}{LIST_MARKER} (?!\[[ xX]\])")
ANY_BULLET = re.compile(rf"^\s*{LIST_MARKER} (?!\[[ xX]\])")
CHECKLIST = re.compile(r"^\s*[-*+] \[[ xX]\]")
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
HAS_JAPANESE = re.compile(JAPANESE)
LANGUAGES = {"ja": "日本語", "en": "英語"}
NOUN_ENDING = re.compile(r"[\u3400-\u9fff\u30a0-\u30ffA-Za-z0-9]$")
SENTENCE_CLOSERS = "」』）) "
REASON_CLAUSE = re.compile(r"(?:ので|ため|ことから|から)、")
CONDITION_CLAUSE = re.compile(r"(?:れば|たら|なら|場合)、")


def unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        inner = value[1:-1]
        return inner.replace('\\"', '"') if value[0] == '"' else inner
    return value


def is_expanded_by_shell(value: str) -> bool:
    return not value.startswith("'") and bool(DYNAMIC_VALUE.search(value))


def read_title(command: str) -> str | None:
    match = TITLE_FLAG.search(command)
    if not match or is_expanded_by_shell(match.group(1)):
        return None
    return unquote(match.group(1))


def read_body(command: str) -> str | None:
    heredoc = HEREDOC.search(command)
    if heredoc:
        return heredoc.group(3)
    match = BODY_FLAG.search(command)
    if match and not is_expanded_by_shell(match.group(1)):
        return unquote(match.group(1))
    return None


def has_body_flag(command: str) -> bool:
    return bool(BODY_FLAG.search(command) or BODY_FILE_FLAG.search(command))


def prose_lines(body: str) -> list[str]:
    lines = []
    in_fence = False
    for line in body.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
        elif not in_fence:
            lines.append(LINK_TARGET.sub("]", CODE_SPAN.sub("", line)))
    return lines


def read_language(cwd: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", cwd, "config", "--get", "pr.language"],
        capture_output=True,
        text=True,
        timeout=3,
    )
    return result.stdout.strip() or None


def check_language(language: str, title: str | None, body: str | None) -> list[str]:
    prose = [
        line
        for line in prose_lines(body or "")
        if line.strip() and not REFERENCE_LINE.match(line.strip())
    ]
    if language == "ja":
        mismatched = (title is not None and not HAS_JAPANESE.search(title)) or (
            bool(prose) and not any(HAS_JAPANESE.search(line) for line in prose)
        )
    else:
        mismatched = any(HAS_JAPANESE.search(text) for text in [title or "", *prose])
    if mismatched:
        return [f"このリポジトリのPRは{LANGUAGES[language]}で書く"]
    return []


def japanese_sentences(lines: list[str]) -> tuple[list[str], list[str]]:
    """Return the Japanese sentences of the prose lines and those ended by a full stop."""
    every, terminated = [], []
    for line in lines:
        if ANY_BULLET.match(line):
            continue
        parts = line.split("。")
        every += [part for part in parts if HAS_JAPANESE.search(part)]
        terminated += [part for part in parts[:-1] if HAS_JAPANESE.search(part)]
    return every, terminated


def check_sentences(lines: list[str]) -> list[str]:
    every, terminated = japanese_sentences(lines)
    problems = []
    if any(NOUN_ENDING.search(s.rstrip(SENTENCE_CLOSERS)) for s in terminated):
        problems.append("文末を述語で終える。名詞や数字で終わる文がある")
    if any(REASON_CLAUSE.search(s) and CONDITION_CLAUSE.search(s) for s in every):
        problems.append("1文に理由と条件を重ねない。文を分ける")
    return problems


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

    top_level = [line for line in lines if TOP_LEVEL_BULLET.match(line)]
    if any(re.match(r"^refs?\s+.*#\d+", line.strip(), re.IGNORECASE) for line in lines):
        problems.append(
            "対象Issueは `Close #N` で参照する。1 Issue = 1 PRに分け、"
            "Refsにしたくなる場合はPRかIssueを分ける。対象Issueがなければ参照は不要"
        )
    if len(top_level) > MAX_BULLETS:
        problems.append(
            f"箇条書きが{len(top_level)}個ある。{MAX_BULLETS}個以内に統合する"
        )
    if any(ANY_BULLET.match(line) and line.rstrip().endswith("。") for line in lines):
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
            "IssueやPRの番号を文中に埋め込まない。"
            "Issueは先頭の `Close #N` の行に書き、PRの番号は書かない"
        )
    if any(MIXED_SPACE.search(line) for line in lines):
        problems.append("本文の日本語と英語の間にスペースを入れない")
    problems += check_sentences(lines)
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
        body = read_body(command)
        if body is not None:
            problems += check_body(body)
        elif has_body_flag(command):
            problems.append(
                "本文をコマンド内に直接書く。`--body \"$(cat <<'EOF' ... EOF)\"` の形にする。"
                "ファイルや変数を経由すると本文を検査できない"
            )
        if title is not None or body is not None:
            language = read_language(event.get("cwd") or os.getcwd())
            if language in LANGUAGES:
                problems += check_language(language, title, body)
            else:
                problems.append(
                    "このリポジトリのPRの言語が未設定か不正。"
                    "ユーザーに英語か日本語かを確認し、"
                    "`git config pr.language en` か `git config pr.language ja` を設定する"
                )
        if problems:
            deny(problems)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
