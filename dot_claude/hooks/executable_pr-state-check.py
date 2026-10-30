#!/usr/bin/env python3
"""Protect review approvals and merges; uncertain PR identity must not authorize a mutation.

The GitHub MCP server that Claude Code cloud sessions use is held to the same rules:
its merges ask outside personal repositories, and since this hook cannot ask it
whether a PR is a draft, its base changes and conversions to draft are denied.
"""

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
    "--subject",
    "--match-head-commit",
    "-A",
    "--author-email",
}
# Personal repositories merge without asking; any other owner's PR waits for the owner.
MERGE_FREE_OWNERS = {"riii111"}
# Codex parses "ask" but runs the command anyway, so its copy of this hook replaces it with "deny".
MERGE_DECISION = "ask"
MERGE_REASON = (
    "マージはownerの確認が必要です。ownerに頼まれたマージだけを実行してください。"
)
API_MERGE = re.compile(r"(?:^|/)repos/(?P<owner>[\w.-]+)/[\w.-]+/pulls/\d+/merge$")
GRAPHQL_MERGE = re.compile(r"\b(?:mergePullRequest|enablePullRequestAutoMerge)\b")
SHELL_TOKEN = re.compile(
    r"""(?P<redirect>\d*(?:>&|<&|<>|>\||>>?|<<?)|&>>?)"""
    r"""|(?P<comment>#[^\n]*)"""
    r"""|(?P<control>&&|\|\||[;&|()\n])"""
    r"""|(?P<word>(?:[^\s;&|()<>'"\\]|\\.|'[^']*'|"(?:[^"\\]|\\.)*")+)"""
)


def segments(command: str) -> list[list[str]]:
    result: list[list[str]] = [[]]
    position = 0
    redirect_target = False
    for match in SHELL_TOKEN.finditer(command):
        if command[position : match.start()].strip():
            raise ValueError("unsupported shell syntax")
        position = match.end()
        raw = match.group()
        if match.lastgroup == "comment":
            continue
        if match.lastgroup == "redirect":
            if "<<" in raw:
                raise ValueError("heredoc requires a separate command")
            redirect_target = True
        elif match.lastgroup == "control":
            if redirect_target:
                raise ValueError("missing redirection target")
            if raw in {"(", ")"}:
                result.extend([[raw], []])
            else:
                result.append([])
        elif redirect_target:
            redirect_target = False
        else:
            words = shlex.split(raw)
            if len(words) != 1:
                raise ValueError("ambiguous shell word")
            result[-1].append(words[0])
    if command[position:].strip() or redirect_target:
        raise ValueError("incomplete shell syntax")
    return [part for part in result if part]


def take_repo(args: list[str]) -> tuple[list[str], list[str]]:
    if args and args[0] in {"-R", "--repo"}:
        return args[:2], args[2:]
    if args and (args[0].startswith("--repo=") or args[0].startswith("-R")):
        return args[:1], args[1:]
    return [], args


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


def api_merge_owner(args: list[str]) -> str | None:
    """The owner of a merge through `gh api`, "" when its owner is unknown, None when it is no merge."""
    # A GET on the merge endpoint only asks whether the PR is merged.
    put = any(
        method.upper() == "PUT"
        for flag, method in zip(args, args[1:])
        if flag in {"-X", "--method"}
    ) or any(arg.upper() in {"-XPUT", "--METHOD=PUT"} for arg in args)
    owner = None
    for arg in args:
        value = arg.split("=", 1)[1] if arg.startswith("-") and "=" in arg else arg
        if GRAPHQL_MERGE.search(value):
            return ""
        match = API_MERGE.search(value)
        if match and put:
            owner = match.group("owner")
    return owner


def merge_owner(
    gh: str, query: list[str], cwd: str, environment, remaining: float
) -> str:
    result = subprocess.run(
        [gh, "pr", "view", *query, "--json", "url"],
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
        timeout=min(5, remaining),
        check=True,
    )
    match = re.match(r"https://github\.com/([^/]+)/", json.loads(result.stdout)["url"])
    if match is None:
        raise ValueError("PR URL is not on GitHub")
    return match.group(1)


def check(command: str, cwd: str) -> tuple[str, str] | None:
    if not re.search(
        r"\bgh\b.*\b(?:pr\b.*\b(?:ready|edit|merge)|api)\b", command, re.DOTALL
    ):
        return None
    merging = False
    try:
        deadline = time.monotonic() + 10
        directories = []
        for part in segments(command):
            if part == ["("]:
                directories.append(cwd)
                continue
            if part == [")"]:
                cwd = directories.pop()
                continue
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
            prefix, args = take_repo(part[1:])
            if args and args[0] == "api":
                owner = api_merge_owner(args[1:])
                if owner is not None and owner not in MERGE_FREE_OWNERS:
                    return MERGE_DECISION, MERGE_REASON
                continue
            if not args or args[0] != "pr":
                continue
            parent_repo, args = take_repo(args[1:])
            if not args or args[0] not in {"edit", "ready", "merge"}:
                continue
            if "--help" in args or "-h" in args:
                continue
            merging = merging or args[0] == "merge"
            query, dangerous = query_args(prefix + parent_repo + args[1:])
            remaining = deadline - time.monotonic()
            if args[0] == "merge":
                if remaining <= 0:
                    raise ValueError("lookup deadline exceeded")
                owner = merge_owner(part[0], query, cwd, environment, remaining)
                if owner not in MERGE_FREE_OWNERS:
                    return MERGE_DECISION, MERGE_REASON
                continue
            if not dangerous:
                continue
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
                return (
                    "deny",
                    "Open済みPRのDraft化・base変更は禁止。承認を保つため操作を止めました。",
                )
    except (
        ValueError,
        TypeError,
        AttributeError,
        IndexError,
        KeyError,
        OSError,
        subprocess.SubprocessError,
    ):
        if merging:
            return MERGE_DECISION, MERGE_REASON
        return (
            "deny",
            "PRがDraftか確認できないため操作を止めました。対象PR・リポジトリ・接続を確認してください。",
        )
    return None


MCP_MERGES = {"merge_pull_request", "enable_pr_auto_merge"}
MCP_DRAFT_UNKNOWN = (
    "GitHub MCPではPRがDraftか確認できないため、base変更・Draft化を止めました。"
    "必要ならownerに頼んでください。"
)


def mcp_check(name: str, tool_input: dict) -> tuple[str, str] | None:
    if not name.startswith("mcp__") or "github" not in name:
        return None
    operation = re.sub(r"^github[._]", "", name.rsplit("__", 1)[-1])
    if operation in MCP_MERGES:
        if tool_input.get("owner") in MERGE_FREE_OWNERS:
            return None
        return MERGE_DECISION, MERGE_REASON
    if operation == "update_pull_request" and (
        "base" in tool_input or tool_input.get("draft") is True
    ):
        return "deny", MCP_DRAFT_UNKNOWN
    return None


def main() -> int:
    event = json.load(sys.stdin)
    name = event.get("tool_name") or ""
    if name.startswith("mcp__"):
        verdict = mcp_check(name, event.get("tool_input") or {})
    else:
        verdict = check(
            (event.get("tool_input") or {}).get("command") or "",
            event.get("cwd") or os.getcwd(),
        )
    if verdict:
        decision, reason = verdict
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": decision,
                        "permissionDecisionReason": reason,
                    }
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
