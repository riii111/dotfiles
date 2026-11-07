#!/usr/bin/env python3
"""Select Main Verify work from a complete, NUL-delimited git diff."""

import argparse
import re
import subprocess
from pathlib import Path

# Only explicitly understood inputs get narrower checks. All other paths run all
# checks, including deleted paths and both sides of renames (--no-renames).
REPO_ONLY = {
    "bin/executable_dotctl",
    "bin/lib/dot/cli.py",
    "tests/test_dot.py",
    "scripts/build-open-apps.sh",
    "scripts/repair-macos-sdk.py",
    "scripts/setup-default-apps.sh",
}
ALL = {"nix", "dot_tools", "repo", "hooks"}
ONDEMAND_DIR = "tests/ondemand/"
# `dotctl test` skips these slow integration tests, so each runs only when its
# own file or a path it exercises changes. Entries ending in "/" are prefixes.
ONDEMAND = {
    "test_affected_activation.py": ("darwin/", "flake.nix", "flake.lock"),
    "test_affected_integration.py": (
        "bin/executable_affected-agent",
        "bin/lib/dot/cli.py",
        "run_after_zz-notify-affected.sh.tmpl",
        ".chezmoiignore",
        "tests/chezmoi/",
    ),
    "test_gh_repo_baseline.py": ("bin/executable_gh-repo-baseline",),
    "test_macos_sdk_repair.py": ("scripts/repair-macos-sdk.py",),
    "test_shell_widget.py": (
        "dot_zshrc.tmpl",
        "dot_zshenv",
        "tests/chezmoi/personal.toml",
    ),
    "test_terminal_queries.py": ("lefthook.yml",),
}
# A push event carries this "before" for a new branch.
NULL_SHA = re.compile(r"0{40}")


def matches(path: str, targets: tuple[str, ...]) -> bool:
    return any(
        path.startswith(target) if target.endswith("/") else path == target
        for target in targets
    )


def select(paths: list[str]) -> set[str]:
    selected: set[str] = set()
    for path in paths:
        for name, targets in ONDEMAND.items():
            if matches(path, targets):
                selected.add(ONDEMAND_DIR + name)
        if path.startswith(ONDEMAND_DIR):
            if path.endswith(".py"):
                selected.add(path)
            continue
        if path.endswith(".md"):
            # These Markdown files are consumed by cloud setup, not just read as docs.
            if path.startswith((".chezmoitemplates/", "dot_codex/skills/")):
                selected.add("cloud")
            continue  # ai-docs always runs.
        if path in REPO_ONLY:
            selected.add("repo")
        # The package recipe also differs per platform, so it builds on macOS too.
        elif path.startswith("dot-tools/") and path != "dot-tools/package.nix":
            selected.update({"dot_tools", "repo", "hooks"})
        elif path.startswith("darwin/"):
            selected.update({"nix", "repo", "hooks"})
        else:
            selected.update(ALL)
    return selected


def full() -> set[str]:
    return ALL | {ONDEMAND_DIR + name for name in ONDEMAND}


def is_commit(revision: str) -> bool:
    return (
        subprocess.run(
            ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def changed_paths(base: str) -> list[str]:
    diff = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD", "--"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    return [
        path.decode("utf-8", errors="surrogateescape")
        for path in diff.split(b"\0")
        if path
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--base", help="pull request base; a bad base fails")
    # A new branch has no before, and a force push can leave it unreachable.
    group.add_argument("--before", help="push before; falls back to --full")
    group.add_argument("--full", action="store_true")
    args = parser.parse_args()
    if args.full or (
        args.before is not None
        and (
            not args.before
            or NULL_SHA.fullmatch(args.before)
            or not is_commit(args.before)
        )
    ):
        selected = full()
    else:
        selected = select(changed_paths(args.base or args.before))
    for name in sorted(ALL | {"cloud"}):
        print(f"{name}={str(name in selected).lower()}")
    # A deleted on-demand test has nothing left to run.
    ondemand = sorted(
        name
        for name in selected
        if name.startswith(ONDEMAND_DIR) and Path(name).is_file()
    )
    print("ondemand=" + " ".join(ondemand))


if __name__ == "__main__":
    main()
