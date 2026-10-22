#!/usr/bin/env python3
"""Stop forced git push and git add --force in Bash commands.

Permission rules match command prefixes, so `git push --force *` also caught
`--force-with-lease`, and a `+` refspec slipped through every rule. This hook reads the
arguments instead. `--force-with-lease` passes; `--force`, `-f` and `+` refspecs ask for
approval, or are denied with `--deny-force-push`. An exception while parsing the command
never blocks it.
"""

from __future__ import annotations

import json
import shlex
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")"}
GIT_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
PUSH_OPTIONS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
ADD_FORCE_LONG = {"--for", "--forc", "--force"}


def split_segments(command: str) -> list[list[str]]:
    lexer = shlex.shlex(
        command.replace("\n", " ; "), posix=True, punctuation_chars=";&|()"
    )
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        tokens = command.replace("\n", " ; ").split()
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in SEPARATORS:
            segments.append([])
        else:
            segments[-1].append(token)
    return [segment for segment in segments if segment]


def git_subcommand(segment: list[str]) -> tuple[str, list[str]] | None:
    for index, token in enumerate(segment):
        if token == "git" or token.endswith("/git"):
            break
    else:
        return None
    rest = segment[index + 1 :]
    while rest and rest[0].startswith("-"):
        rest = rest[2:] if rest[0] in GIT_OPTIONS_WITH_VALUE else rest[1:]
    if not rest:
        return None
    return rest[0], rest[1:]


def short_flags(arg: str, flags_with_value: str = "") -> str:
    letters = ""
    for letter in arg[1:]:
        letters += letter
        if letter in flags_with_value:
            break
    return letters


def is_forced_push(args: list[str]) -> bool:
    skip_value = False
    options_ended = False
    for arg in args:
        if skip_value:
            skip_value = False
            continue
        if options_ended or not arg.startswith("-"):
            if arg.startswith("+"):
                return True
            continue
        if arg == "--":
            options_ended = True
        elif arg == "--force":
            return True
        elif arg in PUSH_OPTIONS_WITH_VALUE:
            skip_value = True
        elif not arg.startswith("--"):
            letters = short_flags(arg, "o")
            if "f" in letters:
                return True
            skip_value = letters.endswith("o") and arg.endswith("o")
    return False


def is_forced_add(args: list[str]) -> bool:
    for arg in args:
        if arg == "--":
            return False
        if arg in ADD_FORCE_LONG:
            return True
        if arg.startswith("-") and not arg.startswith("--") and "f" in arg:
            return True
    return False


def decide(command: str, deny_force_push: bool) -> tuple[str, str] | None:
    for segment in split_segments(command):
        parsed = git_subcommand(segment)
        if parsed is None:
            continue
        subcommand, args = parsed
        if subcommand == "add" and is_forced_add(args):
            return (
                "deny",
                "git add --force/-f is blocked to prevent committing git-excluded files. "
                "Remove the -f/--force flag.",
            )
        if subcommand == "push" and is_forced_push(args):
            if deny_force_push:
                return (
                    "deny",
                    "git push --force, -f and +refspec are blocked. "
                    "Use --force-with-lease instead.",
                )
            return (
                "ask",
                "git push --force, -f or +refspec overwrites the remote branch.",
            )
    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
        command = (event.get("tool_input") or {}).get("command") or ""
        decision = decide(command, "--deny-force-push" in sys.argv[1:])
    except Exception:
        return 0
    if decision is None:
        return 0
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision[0],
                    "permissionDecisionReason": decision[1],
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
