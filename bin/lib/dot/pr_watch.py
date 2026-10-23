"""Run `harnexus-task watch` as a per-user LaunchAgent.

The watch tells each task worker what happened on its PR. It is kept apart from
review-notifier, which notifies the owner, so either can be stopped alone.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from . import launch_agent


def agent(home: Path) -> launch_agent.Agent:
    return launch_agent.Agent(
        label="io.github.riii111.pr-watch",
        command="pr-watch",
        home=home,
        binary=binary_path(home),
        args=("watch",),
        log=home / "Library" / "Logs" / "pr-watch.log",
        process_type="Background",
    )


def install(home: Path, user: str) -> int:
    for path, hint in (
        (config_path(home), "apply it with chezmoi"),
        (binary_path(home), "run `bun run install:task` in the harnexus checkout"),
    ):
        if not path.exists():
            print(f"{path} not found; {hint}", file=sys.stderr)
            return 1
    # Fails before the agent is loaded if the config, a gh account or the GitHub API is not usable.
    # The dry run lists every comment of every open PR, so only its failure is shown.
    status = launch_agent.run_quiet([str(binary_path(home)), "watch", "--dry-run"])
    if status != 0:
        return status
    return launch_agent.install(agent(home), user)


def uninstall(home: Path) -> int:
    status = launch_agent.uninstall(agent(home))
    print("config, state and logs are kept")
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
    # harnexus-task owns the layout of its records, so they are read through it.
    result = subprocess.run(
        [str(binary), "watch", "--status"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, end="", file=sys.stderr)
        return result.returncode
    for line in watched_prs(result.stdout):
        print(line)
    return 0


def logs(home: Path, follow: bool) -> int:
    return launch_agent.logs(agent(home), follow)


def watched_prs(output: str) -> list[str]:
    try:
        shown = json.loads(output)
    except ValueError:
        return [output.rstrip()]
    lines = []
    for pr in shown.get("prs", []) if isinstance(shown, dict) else []:
        reason = pr.get("reason")
        detail = f" ({reason})" if reason else ""
        waiting = " awaiting answer" if pr.get("awaitingAnswer") else ""
        lines.append(
            f"{pr.get('pr')} {pr.get('status')}{detail} "
            f"pending={pr.get('pending', 0)}{waiting}"
        )
    return lines


def binary_path(home: Path) -> Path:
    return home / ".local" / "bin" / "harnexus-task"


def config_path(home: Path) -> Path:
    return home / ".config" / "harnexus" / "pr-watch.json"
