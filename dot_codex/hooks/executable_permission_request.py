#!/usr/bin/env python3

"""Best-effort command policy for cooperative agents.

Direct deny checks fail open when the shell command is not a single parseable
invocation. PermissionRequest auto-allow checks instead require exact forms and
fail closed. Execpolicy rules separately govern sandbox escalation.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


PROTECTED_BRANCHES = {"main", "master"}


def git_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in list(environment):
        if name.startswith("GIT_"):
            del environment[name]
    return environment


def current_branch(cwd: str) -> str | None:
    result = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=cwd,
        env=git_environment(),
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
        env=git_environment(),
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def github_repository(url: str) -> tuple[str, str] | None:
    scp_match = re.fullmatch(r"git@github\.com:([^/\s]+)/([^/\s]+?)(?:\.git)?", url)
    if scp_match:
        return tuple(part.lower() for part in scp_match.groups())
    scp_match = re.fullmatch(
        r"git@([^:\s]+):([^/\s]+)/([^/\s]+?)(?:\.git)?", url
    )
    if scp_match and github_host(scp_match.group(1)):
        return tuple(part.lower() for part in scp_match.groups()[1:])
    parsed = urlparse(url)
    path_match = re.fullmatch(r"/([^/\s]+)/([^/\s]+?)(?:\.git)?", parsed.path)
    if (
        parsed.scheme not in {"https", "ssh"}
        or not github_host(parsed.hostname)
        or path_match is None
    ):
        return None
    return tuple(part.lower() for part in path_match.groups())


def github_host(host: str | None) -> bool:
    if host is None:
        return False
    result = subprocess.run(
        ["ssh", "-G", host],
        check=False,
        capture_output=True,
        text=True,
        timeout=2,
        env=git_environment(),
    )
    if result.returncode != 0:
        return False
    return any(line == "hostname github.com" for line in result.stdout.splitlines())


def checkout_repository(cwd: str) -> tuple[str, str] | None:
    result = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    common_dir = Path(result.stdout.strip()).resolve()
    repository_dir = common_dir.parent if common_dir.name == ".git" else None
    if repository_dir is None:
        return None
    ghq_root = (Path.home() / "ghq" / "github.com").resolve()
    try:
        relative = repository_dir.relative_to(ghq_root)
    except ValueError:
        return None
    if len(relative.parts) != 2:
        return None
    return relative.parts[0].lower(), relative.parts[1].lower()


def urls_match_checkout(urls: list[str], cwd: str) -> bool:
    expected = checkout_repository(cwd)
    return (
        expected is not None
        and bool(urls)
        and all(github_repository(url) == expected for url in urls)
    )


def trusted_repository(cwd: str) -> bool:
    return urls_match_checkout(origin_urls(cwd, push=False), cwd) and urls_match_checkout(
        origin_urls(cwd, push=True), cwd
    )


def is_safe_auth_status(command: str) -> bool:
    try:
        return tuple(shlex.split(command)) == ("gh", "auth", "status")
    except ValueError:
        return False


def is_safe_git_permission_request(command: str, cwd: str) -> bool:
    try:
        argv = tuple(shlex.split(command))
    except ValueError:
        return False

    executable, args = direct_command(command)
    if executable is None or executable.rsplit("/", 1)[-1] != "git":
        return False
    if has_git_environment_override(command):
        return False
    invocation = safe_git_invocation(args, cwd)
    if invocation is None:
        return False
    target_cwd, subcommand, subargs = invocation
    if subcommand == "branch":
        if subargs and tuple(subargs) not in {
            ("--show-current",),
            ("--list",),
            ("-a",),
            ("-r",),
            ("--all",),
            ("--remotes",),
        }:
            return False
    elif subcommand == "fetch":
        if subargs != ["origin"]:
            return False
    elif subcommand == "ls-remote":
        if subargs != ["origin"]:
            return False
    elif subcommand not in {
        "status",
        "diff",
        "log",
        "show",
        "rev-parse",
        "ls-files",
        "switch",
        "add",
        "commit",
        "merge",
        "rebase",
        "cherry-pick",
    }:
        return False

    if git_denial_reason(subcommand, subargs) is not None:
        return False

    return trusted_repository(str(target_cwd))


def direct_command(command: str) -> tuple[str | None, list[str]]:
    try:
        lexer = shlex.shlex(
            command,
            posix=True,
            punctuation_chars="();&|",
        )
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return None, []
    if not tokens or any(token and set(token) <= set("();&|") for token in tokens):
        return None, []
    index = 0
    while index < len(tokens) and re.fullmatch(
        r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[index], re.DOTALL
    ):
        index += 1
    if index >= len(tokens):
        return None, []
    return tokens[index], tokens[index + 1 :]


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


def has_git_environment_override(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return True
    for token in tokens:
        if "=" not in token or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token.split("=", 1)[0]):
            break
        name = token.split("=", 1)[0]
        if name in {
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_INDEX_FILE",
            "GIT_COMMON_DIR",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_EXTERNAL_DIFF",
        } or name.startswith("GIT_CONFIG"):
            return True
    return False


def has_external_helper_config(args: list[str]) -> bool:
    for index, arg in enumerate(args):
        value = None
        if arg == "-c" and index + 1 < len(args):
            value = args[index + 1]
        elif arg.startswith("-c") and len(arg) > 2:
            value = arg[2:]
        if value is not None and (
            value.startswith("diff.external=")
            or value.startswith("filter.")
            or ".textconv=" in value
        ):
            return True
    return False


def safe_git_invocation(
    args: list[str], cwd: str
) -> tuple[str, str, list[str]] | None:
    target = Path(cwd).resolve()
    index = 0
    while index < len(args) and args[index].startswith("-"):
        option = args[index]
        if option == "-C":
            if index + 1 >= len(args):
                return None
            candidate = Path(args[index + 1])
            target = (candidate if candidate.is_absolute() else target / candidate).resolve()
            index += 2
            continue
        if option.startswith("-C") and len(option) > 2:
            target = (target / option[2:]).resolve()
            index += 1
            continue
        return None
    if index >= len(args) or not target.is_dir():
        return None
    return str(target), args[index], args[index + 1 :]


def has_option(args: list[str], option: str) -> bool:
    return any(arg == option or arg.startswith(f"{option}=") for arg in args)


def has_short_flag(args: list[str], flag: str) -> bool:
    return any(
        arg.startswith("-") and not arg.startswith("--") and flag in arg[1:]
        for arg in args
    )


def starts_with(args: list[str], prefix: list[str]) -> bool:
    return args[: len(prefix)] == prefix


def git_denial_reason(subcommand: str | None, subargs: list[str]) -> str | None:
    if subcommand == "reset" and has_option(subargs, "--hard"):
        return "Hard reset is forbidden."
    if subcommand == "restore" and any(arg in {".", ":/"} for arg in subargs):
        staged = has_option(subargs, "--staged") or has_short_flag(subargs, "S")
        worktree = has_option(subargs, "--worktree") or has_short_flag(subargs, "W")
        if not staged or worktree:
            return "Restoring the entire working tree is forbidden."
    if subcommand == "checkout" and any(arg in {".", ":/"} for arg in subargs):
        return "Discarding the entire working tree is forbidden."
    if subcommand == "stash" and subargs and subargs[0] in {"clear", "drop"}:
        return "Deleting stash entries is forbidden; leave them intact."
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
    if subcommand == "switch" and (
        has_option(subargs, "--force")
        or has_option(subargs, "--force-create")
        or has_option(subargs, "--discard-changes")
        or has_short_flag(subargs, "f")
        or has_short_flag(subargs, "C")
    ):
        return "Forced branch switching is forbidden."
    if subcommand == "branch" and (
        has_short_flag(subargs, "D")
        or (
            has_option(subargs, "--delete")
            and (has_option(subargs, "--force") or has_short_flag(subargs, "f"))
        )
    ):
        return "Deleting a branch is forbidden."
    if subcommand == "fetch" and (
        has_option(subargs, "--force")
        or has_short_flag(subargs, "f")
        or has_option(subargs, "--update-head-ok")
        or any(arg.startswith("+") for arg in subargs)
    ):
        return "Forced fetch is forbidden."
    if subcommand == "push" and (
        has_option(subargs, "--force")
        or has_option(subargs, "--force-with-lease")
        or has_option(subargs, "--mirror")
        or has_option(subargs, "--delete")
        or has_option(subargs, "--prune")
        or has_short_flag(subargs, "f")
        or has_short_flag(subargs, "d")
        or any(arg.startswith(("+", ":")) for arg in subargs)
    ):
        return "Destructive push is forbidden."
    if subcommand in {"diff", "show", "log"} and any(
        arg in {"--ext-diff", "--textconv"} or arg.startswith("--textconv=")
        for arg in subargs
    ):
        return "External Git diff helpers are forbidden."
    return None


def shell_tokens(command: str) -> list[str]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars="();&|")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def compound_denial_reason(command: str) -> str | None:
    try:
        tokens = shell_tokens(command)
    except ValueError:
        return None
    for index, token in enumerate(tokens):
        if token.rsplit("/", 1)[-1] != "git":
            continue
        segment = []
        for candidate in tokens[index + 1 :]:
            if candidate in {";", "&", "|", "(", ")"}:
                break
            segment.append(candidate)
        if has_external_helper_config(segment):
            return "External Git diff helpers are forbidden."
        reason = git_denial_reason(*git_command(segment))
        if reason is not None:
            return reason
    if re.search(r"\bgit(?:\s+[^;&|]*)?\s+reset\s+[^;&|]*--hard(?:[^A-Za-z0-9_-]|$)", command):
        return "Hard reset is forbidden."
    if re.search(r"\bgit(?:\s+[^;&|]*)?\s+add\s+[^;&|]*\s-f(?:\s'\"]|$)", command):
        return "Force-add is forbidden."
    if re.search(r"\brm\s+[^;&|]*-[^;&|]*r", command):
        return "Recursive file deletion is forbidden."
    if any(token.startswith("GIT_EXTERNAL_DIFF=") for token in shell_tokens(command)):
        return "External Git diff helpers are forbidden."
    return None


def denial_reason(command: str) -> str | None:
    executable, args = direct_command(command)
    executable_name = None if executable is None else executable.rsplit("/", 1)[-1]

    if executable_name == "gh" and starts_with(args, ["auth", "token"]):
        return "GitHub access-token output is forbidden."
    if executable_name == "gh" and starts_with(args, ["auth", "status"]):
        status_args = args[2:]
        if has_option(status_args, "--show-token") or has_short_flag(status_args, "t"):
            return "GitHub access-token output is forbidden."
    if executable_name == "gh" and starts_with(args, ["repo", "delete"]):
        return "Repository deletion is forbidden."
    if executable_name == "gh" and (
        starts_with(args, ["ssh-key", "add"])
        or starts_with(args, ["gpg-key", "add"])
        or (
            starts_with(args, ["auth"])
            and len(args) >= 2
            and args[1] in {"login", "refresh", "setup-git"}
        )
    ):
        return "Changing persistent GitHub authentication is forbidden."

    if executable_name == "gcloud" and starts_with(
        args, ["auth", "print-access-token"]
    ):
        return "Google Cloud access-token output is forbidden."
    if executable_name == "gcloud" and starts_with(args, ["projects", "delete"]):
        return "Cloud project deletion is forbidden."
    if executable_name == "gcloud" and (
        starts_with(args, ["storage", "rm"])
        or starts_with(args, ["run", "jobs", "delete"])
        or starts_with(args, ["run", "services", "delete"])
        or starts_with(args, ["iam", "service-accounts", "keys", "create"])
    ):
        return "Destructive cloud or credential mutation is forbidden."

    if executable_name == "git":
        if has_git_environment_override(command):
            return "Git environment overrides are forbidden."
        if has_external_helper_config(args):
            return "External Git diff helpers are forbidden."
        subcommand, subargs = git_command(args)
        reason = git_denial_reason(subcommand, subargs)
        if reason is not None:
            return reason

    if executable_name == "terraform":
        terraform_args = [arg for arg in args if not arg.startswith("-chdir=")]
        if terraform_args and (
            terraform_args[0] in {"apply", "destroy", "taint", "import", "force-unlock"}
            or starts_with(terraform_args, ["state", "rm"])
            or starts_with(terraform_args, ["state", "mv"])
            or starts_with(terraform_args, ["workspace", "delete"])
        ):
            return "Terraform state mutation is forbidden."

    if executable_name in {"sudo", "su"}:
        return "Privilege escalation and user switching are forbidden."
    if executable_name == "chmod" and "777" in args:
        return "World-writable permissions are forbidden."
    if executable_name == "rm" and (
        has_option(args, "--recursive")
        or has_short_flag(args, "r")
        or has_short_flag(args, "R")
    ):
        return "Recursive file deletion is forbidden."
    if executable_name == "find" and has_option(args, "-delete"):
        return "Recursive deletion through find is forbidden."
    if executable_name == "chezmoi" and args and args[0] in {"purge", "destroy"}:
        return "Deleting chezmoi source or target state is forbidden."
    if executable_name == "bq" and starts_with(args, ["rm"]):
        return "BigQuery resource deletion is forbidden."

    if executable is None:
        return compound_denial_reason(command)
    return compound_denial_reason(command)


def is_safe_push(command: str, cwd: str) -> bool:
    try:
        argv = shlex.split(command)
    except ValueError:
        return False

    branch = current_branch(cwd)
    if branch is None or branch in PROTECTED_BRANCHES:
        return False

    if not trusted_repository(cwd):
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
        and not is_safe_git_permission_request(command, cwd)
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
