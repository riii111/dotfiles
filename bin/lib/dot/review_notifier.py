"""Build tools/review-notifier and manage it as a per-user LaunchAgent."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from . import launch_agent


SOURCE_DIR = Path("tools") / "review-notifier"


def agent(home: Path) -> launch_agent.Agent:
    return launch_agent.Agent(
        label="io.github.riii111.review-notifier",
        command="review-notifier",
        home=home,
        binary=binary_path(home),
        args=("run",),
        log=home / "Library" / "Logs" / "review-notifier.log",
        process_type="Interactive",
    )


def install(repo_root: Path, home: Path, user: str) -> int:
    config = config_path(home)
    if not config.exists():
        print(
            f"{config} not found; copy {repo_root / SOURCE_DIR / 'config.example.json'} and edit it",
            file=sys.stderr,
        )
        return 1
    status = build(repo_root, home)
    if status != 0:
        return status
    # Fails before the agent is loaded if the config, a command or the GitHub API is not usable.
    status = launch_agent.run([str(binary_path(home)), "check"])
    if status != 0:
        return status
    return launch_agent.install(agent(home), user)


def uninstall(home: Path) -> int:
    status = launch_agent.uninstall(agent(home))
    binary_path(home).unlink(missing_ok=True)
    print("config, state, logs and review worktrees are kept")
    return status


def start(home: Path) -> int:
    return launch_agent.start(agent(home))


def stop(home: Path) -> int:
    return launch_agent.stop(agent(home))


def status(home: Path) -> int:
    launch_agent.print_loaded(agent(home))
    binary = binary_path(home)
    if not binary.exists():
        print(f"{binary} not found")
        return 1
    return launch_agent.run([str(binary), "status"])


def logs(home: Path, follow: bool) -> int:
    return launch_agent.logs(agent(home), follow)


def build(repo_root: Path, home: Path) -> int:
    go = shutil.which("go")
    if go is None:
        print("go not found; run `dotctl sync-nix-profile` first", file=sys.stderr)
        return 1
    target = binary_path(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f".{target.name}.tmp")
    status = launch_agent.run(
        [go, "build", "-o", str(tmp), "."], repo_root / SOURCE_DIR
    )
    if status != 0:
        tmp.unlink(missing_ok=True)
        return status
    os.replace(tmp, target)
    return 0


def binary_path(home: Path) -> Path:
    return home / ".local" / "bin" / "review-notifier"


def config_path(home: Path) -> Path:
    return home / ".config" / "review-notifier" / "config.json"
