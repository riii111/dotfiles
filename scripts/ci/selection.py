#!/usr/bin/env python3
"""Select Main Verify work from a complete, NUL-delimited git diff."""

import argparse
import re
import subprocess
from pathlib import Path

# Only explicitly understood inputs get narrower checks. All other paths run all
# checks and on-demand tests, as --full does, including deleted paths and both
# sides of renames (--no-renames).
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
# A path that already runs everything (see select) needs no entry, so only paths
# the narrow categories cover are listed; test_select keeps the table to those.
ONDEMAND = {
    "test_affected_activation.py": ("darwin/",),
    "test_affected_integration.py": ("bin/lib/dot/cli.py",),
    "test_gh_repo_baseline.py": (),
    "test_macos_sdk_repair.py": ("scripts/repair-macos-sdk.py",),
    "test_shell_widget.py": (),
    "test_terminal_queries.py": (),
}
# The tests mark themselves, so a new macOS-only test needs no entry here.
REQUIRES_DARWIN = re.compile(r"^REQUIRES_DARWIN = True$", re.M)
DARWIN_ONDEMAND = {
    test.name
    for test in (Path(__file__).resolve().parents[2] / ONDEMAND_DIR).glob("test_*.py")
    if REQUIRES_DARWIN.search(test.read_text())
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
        if path.endswith(".md"):
            # Cloud setup and the reply reminder consume these Markdown files, not just people.
            # No on-demand target is Markdown, so a README beside one selects nothing.
            if path.startswith((".chezmoitemplates/", "dot_codex/skills/")):
                selected.add("cloud")
            continue  # ai-docs always runs.
        for name, targets in ONDEMAND.items():
            if matches(path, targets):
                selected.add(ONDEMAND_DIR + name)
        if path.startswith(ONDEMAND_DIR) and path.endswith(".py"):
            # The repo checks lint these, and dotctl test skips running them.
            selected.add("repo")
            if Path(path).name.startswith("test_"):
                selected.add(path)
            else:
                # Any on-demand test may import a helper.
                selected.update(all_ondemand())
            continue
        if path in REPO_ONLY:
            selected.add("repo")
        # The CLI profile and both Darwin configurations consume the package recipe.
        elif path.startswith("dot-tools/") and path != "dot-tools/package.nix":
            selected.update({"dot_tools", "repo", "hooks"})
        elif path.startswith("darwin/"):
            selected.update({"nix", "repo", "hooks"})
        else:
            # Unknown effects may reach any on-demand target too.
            selected.update(full())
    return selected


def all_ondemand() -> set[str]:
    return {ONDEMAND_DIR + name for name in ONDEMAND}


def full() -> set[str]:
    return ALL | all_ondemand()


def ondemand_lists(selected: set[str]) -> tuple[list[str], list[str]]:
    """Split the selected on-demand tests into Linux and macOS runs."""
    tests = sorted(name for name in selected if name.startswith(ONDEMAND_DIR))
    darwin = [name for name in tests if Path(name).name in DARWIN_ONDEMAND]
    return [name for name in tests if name not in darwin], darwin


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
    linux, darwin = ondemand_lists(
        {
            name
            for name in selected
            if not name.startswith(ONDEMAND_DIR) or Path(name).is_file()
        }
    )
    print("ondemand=" + " ".join(linux))
    print("ondemand_darwin=" + " ".join(darwin))


if __name__ == "__main__":
    main()
