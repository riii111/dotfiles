#!/usr/bin/env python3
"""Select Main Verify work from a complete, NUL-delimited git diff."""

import argparse
import subprocess

# Only explicitly understood inputs get narrower checks. All other paths run all
# checks, including deleted paths and both sides of renames (--no-renames).
REPO_ONLY = {
    "bin/executable_dotctl",
    "bin/lib/dot/cli.py",
    "tests/test_dot.py",
    "scripts/build-open-apps.sh",
    "scripts/repair-macos-sdk.py",
    "scripts/setup-default-apps.sh",
    "tests/test_macos_sdk_repair.py",
}
ALL = {"nix", "dot_tools", "repo", "hooks"}


def select(paths: list[str]) -> set[str]:
    selected: set[str] = set()
    for path in paths:
        if path.endswith(".md"):
            # These Markdown files are consumed by cloud setup, not just read as docs.
            if path.startswith((".chezmoitemplates/", "dot_codex/skills/")):
                selected.add("cloud")
            continue  # ai-docs always runs.
        if path in REPO_ONLY:
            selected.add("repo")
        elif path.startswith("dot-tools/"):
            selected.update({"dot_tools", "repo", "hooks"})
        elif path.startswith("darwin/"):
            selected.update({"nix", "repo", "hooks"})
        else:
            selected.update(ALL)
    return selected


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    if args.full:
        selected = ALL
    else:
        if not args.base:
            parser.error("--base is required unless --full is set")
        diff = subprocess.run(
            [
                "git",
                "diff",
                "--no-renames",
                "--name-only",
                "-z",
                args.base,
                "HEAD",
                "--",
            ],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        selected = select(
            [
                path.decode("utf-8", errors="surrogateescape")
                for path in diff.split(b"\0")
                if path
            ]
        )
    for name in sorted(ALL | {"cloud"}):
        print(f"{name}={str(name in selected).lower()}")


if __name__ == "__main__":
    main()
