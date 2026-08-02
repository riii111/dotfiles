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


def shell_segments(command: str) -> list[list[str]]:
    try:
        lexer = shlex.shlex(
            command.replace("\n", ";"),
            posix=True,
            punctuation_chars="();&|",
        )
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return []

    segments: list[list[str]] = []
    segment: list[str] = []
    for token in tokens:
        if token and set(token) <= set("();&|"):
            if segment:
                segments.append(segment)
                segment = []
            continue
        segment.append(token)
    if segment:
        segments.append(segment)
    return segments


def command_and_args(segment: list[str]) -> tuple[str | None, list[str]]:
    index = 0
    while index < len(segment) and re.fullmatch(
        r"[A-Za-z_][A-Za-z0-9_]*=.*", segment[index]
    ):
        index += 1
    if index < len(segment) and segment[index] == "command":
        index += 1
    if index < len(segment) and segment[index] == "env":
        index += 1
        options_with_values = {"-C", "-S", "-u", "--chdir", "--split-string", "--unset"}
        while index < len(segment):
            arg = segment[index]
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", arg):
                index += 1
            elif arg in options_with_values:
                index += 2
            elif arg.startswith("-"):
                index += 1
            else:
                break
    if index >= len(segment):
        return None, []
    return segment[index], segment[index + 1 :]


def git_command(args: list[str]) -> tuple[str | None, list[str]]:
    index = 0
    options_with_values = {
        "-C",
        "-c",
        "--config-env",
        "--exec-path",
        "--git-dir",
        "--namespace",
        "--super-prefix",
        "--work-tree",
    }
    while index < len(args) and args[index].startswith("-"):
        option = args[index]
        index += 1
        if option in options_with_values:
            index += 1
    if index >= len(args):
        return None, []
    return args[index], args[index + 1 :]


def has_option(args: list[str], option: str) -> bool:
    return any(arg == option or arg.startswith(f"{option}=") for arg in args)


def has_short_flag(args: list[str], flag: str) -> bool:
    return any(
        arg.startswith("-") and not arg.startswith("--") and flag in arg[1:]
        for arg in args
    )


def sequence_index(args: list[str], sequence: list[str]) -> int | None:
    for index in range(len(args) - len(sequence) + 1):
        if args[index : index + len(sequence)] == sequence:
            return index
    return None


def denial_reason(command: str) -> str | None:
    for segment in shell_segments(command):
        executable, args = command_and_args(segment)

        if (
            executable is not None
            and executable.rsplit("/", 1)[-1] in {"bash", "sh", "zsh"}
            and len(args) >= 2
            and args[0] in {"-c", "-lc", "-cl"}
        ):
            nested_reason = denial_reason(args[1])
            if nested_reason is not None:
                return nested_reason

        if executable == "gh" and sequence_index(args, ["auth", "token"]) is not None:
            return "GitHub access-token output is forbidden."
        if executable == "gh":
            status_index = sequence_index(args, ["auth", "status"])
            status_args = [] if status_index is None else args[status_index + 2 :]
            if status_index is not None and (
                has_option(status_args, "--show-token")
                or has_short_flag(status_args, "t")
            ):
                return "GitHub access-token output is forbidden."
        if executable == "gh" and sequence_index(args, ["repo", "delete"]) is not None:
            return "Repository deletion is forbidden."

        if (
            executable == "gcloud"
            and sequence_index(args, ["auth", "print-access-token"]) is not None
        ):
            return "Google Cloud access-token output is forbidden."
        if (
            executable == "gcloud"
            and sequence_index(args, ["projects", "delete"]) is not None
        ):
            return "Cloud project deletion is forbidden."

        if executable == "git":
            subcommand, subargs = git_command(args)
            if subcommand == "reset" and has_option(subargs, "--hard"):
                return "Hard reset is forbidden."
            if subcommand == "add" and (
                has_option(subargs, "--force") or has_short_flag(subargs, "f")
            ):
                return "Force-add is forbidden."
            if subcommand == "clean" and (
                has_option(subargs, "--force") or has_short_flag(subargs, "f")
            ):
                return "Forced clean is forbidden."
            if subcommand == "gc" and (
                "--prune=now" in subargs
                or any(
                    subargs[index : index + 2] == ["--prune", "now"]
                    for index in range(len(subargs) - 1)
                )
            ):
                return "Immediate Git object pruning is forbidden."
            if subcommand == "push" and (
                has_option(subargs, "--force")
                or has_option(subargs, "--force-with-lease")
                or has_option(subargs, "--mirror")
                or has_option(subargs, "--delete")
                or has_short_flag(subargs, "f")
                or any(arg.startswith(("+", ":")) for arg in subargs)
            ):
                return "Destructive push is forbidden."

        if executable == "terraform":
            terraform_args = [arg for arg in args if not arg.startswith("-chdir=")]
            if terraform_args and terraform_args[0] in {"apply", "destroy"}:
                return "Terraform state mutation is forbidden."

        if executable in {"sudo", "su"}:
            return "Privilege escalation and user switching are forbidden."
        if executable == "chmod" and "777" in args:
            return "World-writable permissions are forbidden."

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
    event_name = event.get("hook_event_name")
    if not isinstance(command, str) or not isinstance(cwd, str):
        return 0
    reason = denial_reason(command)
    if reason is not None:
        if event_name == "PreToolUse":
            json.dump(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                },
                sys.stdout,
            )
            return 0
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
    if event_name != "PermissionRequest":
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
