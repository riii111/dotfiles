#!/usr/bin/env python3

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
import tomllib
from contextlib import contextmanager
from pathlib import Path


SESSION_VERSION = 2
ORCHESTRATION_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class StateError(ValueError):
    pass


def config_path() -> Path:
    xdg = Path(value) if (value := os.environ.get("XDG_CONFIG_HOME")) else None
    base = xdg if xdg and xdg.is_absolute() else Path.home() / ".config"
    return base / "codex-task-orchestrator" / "config.toml"


def state_path(orchestration_id: str) -> Path:
    xdg = Path(value) if (value := os.environ.get("XDG_STATE_HOME")) else None
    base = xdg if xdg and xdg.is_absolute() else Path.home() / ".local" / "state"
    return base / "codex-task-orchestrator" / orchestration_id / "sessions.json"


def load_orchestration(orchestration_id: str) -> dict:
    if not ORCHESTRATION_ID.fullmatch(orchestration_id):
        raise StateError("invalid orchestration ID")

    path = config_path()
    try:
        with path.open("rb") as file:
            config = tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise StateError(f"could not read configuration at {path}: {error}") from error

    orchestration = config.get("orchestrations", {}).get(orchestration_id)
    if not isinstance(orchestration, dict):
        raise StateError(f"orchestration {orchestration_id!r} is not registered")

    required = ("parent_thread_id", "repository", "task_source")
    if any(
        not isinstance(orchestration.get(key), str) or not orchestration[key].strip()
        for key in required
    ):
        raise StateError("orchestration configuration has an empty required value")
    if not REPOSITORY.fullmatch(orchestration["repository"]):
        raise StateError("repository must use owner/repository form")

    return {
        "orchestration_id": orchestration_id,
        **{key: orchestration[key] for key in required},
        "sessions_path": str(state_path(orchestration_id)),
    }


def empty_sessions(parent_thread_id: str) -> dict:
    return {
        "version": SESSION_VERSION,
        "parent_thread_id": parent_thread_id,
        "tasks": {},
    }


def load_sessions(path: Path, parent_thread_id: str) -> dict:
    if not path.exists():
        return empty_sessions(parent_thread_id)
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(f"could not read sessions at {path}: {error}") from error

    if not isinstance(data, dict) or data.get("version") not in (1, SESSION_VERSION):
        raise StateError("unsupported sessions version")
    if data.get("parent_thread_id") != parent_thread_id or not isinstance(
        data.get("tasks"), dict
    ):
        raise StateError("sessions parent or tasks do not match the orchestration")

    normalized = empty_sessions(parent_thread_id)
    for task_id, task in data["tasks"].items():
        if not isinstance(task_id, str) or not task_id or not isinstance(task, dict):
            raise StateError("sessions contain an invalid task entry")
        child_thread_id = task.get("child_thread_id")
        if not isinstance(child_thread_id, str) or not child_thread_id:
            raise StateError(f"task {task_id} has no child thread ID")
        normalized_task = {"child_thread_id": child_thread_id}
        if "pull_request" in task:
            normalized_task["pull_request"] = validate_pull_request(
                task["pull_request"]
            )
        normalized["tasks"][task_id] = normalized_task
    return normalized


def validate_pull_request(pull_request: object) -> dict:
    if not isinstance(pull_request, dict):
        raise StateError("pull request association must be an object")
    repository = pull_request.get("repository")
    number = pull_request.get("number")
    if not isinstance(repository, str) or not REPOSITORY.fullmatch(repository):
        raise StateError("pull request repository must use owner/repository form")
    if not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise StateError("pull request number must be a positive integer")
    return {"repository": repository, "number": number}


def write_sessions(path: Path, sessions: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(sessions, temporary, ensure_ascii=False, indent=2, sort_keys=True)
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        temporary_path.chmod(0o600)
        os.replace(temporary_path, path)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()


@contextmanager
def lock_sessions(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(".lock")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def record_session(orchestration_id: str, task_id: str, child_thread_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        existing = sessions["tasks"].get(task_id)
        if existing:
            if existing["child_thread_id"] != child_thread_id:
                raise StateError(
                    f"task {task_id} is already associated with another thread"
                )
            return sessions
        if not task_id or not child_thread_id:
            raise StateError("task ID and child thread ID must not be empty")
        sessions["tasks"][task_id] = {"child_thread_id": child_thread_id}
        write_sessions(path, sessions)
        return sessions


def record_pull_request(
    orchestration_id: str, task_id: str, repository: str, number: int
) -> dict:
    context = load_orchestration(orchestration_id)
    if repository != context["repository"]:
        raise StateError("pull request repository does not match the orchestration")
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        task = sessions["tasks"].get(task_id)
        if task is None:
            raise StateError(f"task {task_id} has no child session")
        pull_request = validate_pull_request(
            {"repository": repository, "number": number}
        )
        existing = task.get("pull_request")
        if existing and existing != pull_request:
            raise StateError(
                f"task {task_id} is already associated with another pull request"
            )
        if existing == pull_request:
            return sessions
        task["pull_request"] = pull_request
        write_sessions(path, sessions)
        return sessions


def load_tasks(path: Path) -> dict[str, dict]:
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(
            f"could not read normalized tasks at {path}: {error}"
        ) from error
    raw_tasks = payload.get("tasks") if isinstance(payload, dict) else None
    if not isinstance(raw_tasks, list):
        raise StateError("normalized tasks must contain a tasks array")

    tasks = {}
    for index, raw in enumerate(raw_tasks):
        if (
            not isinstance(raw, dict)
            or not isinstance(raw.get("id"), str)
            or not raw["id"]
        ):
            raise StateError("each normalized task must have a non-empty ID")
        task_id = raw["id"]
        if task_id in tasks:
            raise StateError(f"duplicate task ID: {task_id}")
        dependencies = raw.get("dependencies", [])
        if not isinstance(dependencies, list) or any(
            not isinstance(value, str) or not value for value in dependencies
        ):
            raise StateError(f"task {task_id} has invalid dependencies")
        if len(dependencies) != len(set(dependencies)):
            raise StateError(f"task {task_id} has duplicate dependencies")
        order = raw.get("order", index)
        if not isinstance(order, int) or isinstance(order, bool):
            raise StateError(f"task {task_id} has an invalid order")
        tasks[task_id] = {"dependencies": dependencies, "order": order}

    for task_id, task in tasks.items():
        for dependency in task["dependencies"]:
            if dependency not in tasks:
                raise StateError(f"task {task_id} depends on missing task {dependency}")
            if dependency == task_id:
                raise StateError(f"task {task_id} depends on itself")
    validate_acyclic(tasks)
    return tasks


def validate_acyclic(tasks: dict[str, dict]) -> None:
    visiting = set()
    visited = set()

    def visit(task_id: str) -> None:
        if task_id in visiting:
            raise StateError(f"dependency cycle includes task {task_id}")
        if task_id in visited:
            return
        visiting.add(task_id)
        for dependency in tasks[task_id]["dependencies"]:
            visit(dependency)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in tasks:
        visit(task_id)


def plan(
    orchestration_id: str,
    tasks_path: Path,
    completed_ids: list[str],
    maximum_parallelism: int,
) -> dict:
    if maximum_parallelism < 1:
        raise StateError("maximum parallelism must be positive")
    context = load_orchestration(orchestration_id)
    sessions = load_sessions(
        Path(context["sessions_path"]), context["parent_thread_id"]
    )
    tasks = load_tasks(tasks_path)
    completed = set(completed_ids)
    unknown_completed = completed - tasks.keys()
    unknown_launched = sessions["tasks"].keys() - tasks.keys()
    if unknown_completed or unknown_launched:
        raise StateError(
            "completed or launched tasks are absent from the current task source"
        )

    launched = set(sessions["tasks"])
    active = launched - completed
    available = max(0, maximum_parallelism - len(active))
    ready = [
        task_id
        for task_id, task in tasks.items()
        if task_id not in completed | launched
        and set(task["dependencies"]) <= completed
    ]
    ready.sort(key=lambda task_id: (tasks[task_id]["order"], task_id))
    selected = ready[:available]

    waiting = {
        task_id: sorted(set(task["dependencies"]) - completed)
        for task_id, task in tasks.items()
        if task_id not in completed | launched and set(task["dependencies"]) - completed
    }
    return {
        "selected": selected,
        "completed": sorted(completed),
        "launched_uncompleted": sorted(active),
        "waiting_dependencies": waiting,
        "capacity_deferred": ready[available:],
        "available_slots": available,
        "sessions_path": context["sessions_path"],
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Manage task orchestration state")
    commands = root.add_subparsers(dest="command", required=True)

    context = commands.add_parser("context")
    context.add_argument("orchestration_id")

    planning = commands.add_parser("plan")
    planning.add_argument("orchestration_id")
    planning.add_argument("--tasks", type=Path, required=True)
    planning.add_argument("--completed", action="append", default=[])
    planning.add_argument("--max-parallelism", type=int, required=True)

    session = commands.add_parser("record-session")
    session.add_argument("orchestration_id")
    session.add_argument("--task-id", required=True)
    session.add_argument("--child-thread-id", required=True)

    pull_request = commands.add_parser("record-pr")
    pull_request.add_argument("orchestration_id")
    pull_request.add_argument("--task-id", required=True)
    pull_request.add_argument("--repository", required=True)
    pull_request.add_argument("--number", type=int, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        if arguments.command == "context":
            output = load_orchestration(arguments.orchestration_id)
            output["sessions"] = load_sessions(
                Path(output["sessions_path"]), output["parent_thread_id"]
            )
        elif arguments.command == "plan":
            output = plan(
                arguments.orchestration_id,
                arguments.tasks,
                arguments.completed,
                arguments.max_parallelism,
            )
        elif arguments.command == "record-session":
            output = record_session(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.child_thread_id,
            )
        else:
            output = record_pull_request(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.repository,
                arguments.number,
            )
    except StateError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
