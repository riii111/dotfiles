#!/usr/bin/env python3
"""Deny GitHub comment posting from shell commands and GitHub MCP tools.

Commands are matched by their parsed words. Requests that scripts build at
runtime or read from files are not recognized. Issue comments stay available
through `gh issue`; the API and connector share PR and Issue comment endpoints,
so they stay denied for both.
"""

import json
import re
import shlex
import sys


REASON = "GitHub comment posting is forbidden. Return the draft in chat."
# Operations of the Codex GitHub connector that publish comment text.
COMMENT_TOOLS = {
    "add_comment_to_issue",
    "add_review_to_pr",
    "reply_to_review_comment",
    "update_issue_comment",
    "update_review_comment",
}
COMMENT_ENDPOINT = re.compile(
    r"repos/[^/\s]+/[^/\s]+/(?:issues|pulls)/(?:\d+/)?(?:comments|reviews)\b"
)
COMMENT_MUTATION = re.compile(
    r"\b(?:addComment|updateIssueComment|addPullRequestReview\w*|"
    r"submitPullRequestReview|updatePullRequestReview\w*)\s*\("
)
SHELLS = {"bash", "sh", "zsh"}
OPERATORS = set(";&|()<>")


def comment_tool(name: str) -> bool:
    if not name.startswith("mcp__") or "github" not in name:
        return False
    operation = re.sub(r"^github[._]", "", name.rsplit("__", 1)[-1])
    return operation in COMMENT_TOOLS


def segments(command: str):
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        words = list(lexer)
    except ValueError:
        words = command.split()
    segment = []
    for word in words:
        if set(word) <= OPERATORS:
            yield segment
            segment = []
        else:
            segment.append(word)
    yield segment


def api_writes(args: list[str]) -> bool:
    method, has_fields = None, False
    remaining = iter(args)
    for arg in remaining:
        if arg in {"-X", "--method"}:
            method = next(remaining, "")
        elif arg.startswith("--method="):
            method = arg.split("=", 1)[1]
        elif arg.startswith("-X"):
            method = arg[2:]
        elif arg.startswith(("-f", "-F", "--field", "--raw-field", "--input")):
            has_fields = True
    # gh api sends fields as a POST body unless another method is given.
    method = (method or ("POST" if has_fields else "GET")).upper()
    return method in {"POST", "PATCH", "PUT"}


def posts_comment(words: list[str]) -> bool:
    while words and (
        re.match(r"[A-Za-z_]\w*=", words[0]) or words[0] in {"env", "command", "exec"}
    ):
        words = words[1:]
    if not words:
        return False
    executable, args = words[0].rsplit("/", 1)[-1], words[1:]
    if (
        executable in SHELLS
        and len(args) >= 2
        and args[0].startswith("-")
        and "c" in args[0]
    ):
        return comment_command(args[1])
    if executable != "gh":
        return False
    while args and args[0] in {"-R", "--repo", "--hostname"}:
        args = args[2:]
    if args[:2] in (["pr", "comment"], ["pr", "review"]):
        return True
    if len(args) >= 2 and args[0] == "pr" and args[1] in {"close", "reopen"}:
        return any(
            arg in {"-c", "--comment"} or arg.startswith("--comment=") for arg in args
        )
    if args[:1] == ["api"]:
        request = " ".join(args)
        return bool(
            COMMENT_ENDPOINT.search(request) or COMMENT_MUTATION.search(request)
        ) and api_writes(args)
    return False


def comment_command(command: str) -> bool:
    return any(posts_comment(words) for words in segments(command))


def denied(event: dict) -> bool:
    name = event.get("tool_name", "")
    if name.startswith("mcp__"):
        return comment_tool(name)
    command = event.get("tool_input", {}).get("command")
    return isinstance(command, str) and comment_command(command)


def main() -> int:
    event = json.load(sys.stdin)
    if denied(event):
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": REASON,
                }
            },
            sys.stdout,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
