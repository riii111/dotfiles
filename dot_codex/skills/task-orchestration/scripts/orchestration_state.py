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


SESSION_VERSION = 3
MERGES_VERSION = 1
ORCHESTRATION_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
PULL_REQUEST_NUMBER = re.compile(r"^[1-9][0-9]*$")


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


def merges_path(orchestration_id: str) -> Path:
    return state_path(orchestration_id).with_name("merges.json")


def load_orchestration(orchestration_id: str) -> dict:
    if not ORCHESTRATION_ID.fullmatch(orchestration_id):
        raise StateError("invalid orchestration ID")

    path = config_path()
    try:
        with path.open("rb") as file:
            config = tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise StateError(f"could not read configuration at {path}: {error}") from error

    orchestrations = config.get("orchestrations", {})
    if not isinstance(orchestrations, dict):
        raise StateError("configuration orchestrations must be a table")
    orchestration = orchestrations.get(orchestration_id)
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
        "merges_path": str(merges_path(orchestration_id)),
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

    if not isinstance(data, dict) or data.get("version") not in (1, 2, SESSION_VERSION):
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
        creation = task.get("creation")
        if isinstance(child_thread_id, str) and child_thread_id:
            if creation is not None:
                raise StateError(f"task {task_id} has conflicting creation state")
            normalized_task = {"child_thread_id": child_thread_id}
            if "pull_request" in task:
                normalized_task["pull_request"] = validate_pull_request(
                    task["pull_request"]
                )
        elif data["version"] == SESSION_VERSION:
            normalized_task = {"creation": validate_creation(task_id, creation)}
            if "pull_request" in task:
                raise StateError(f"task {task_id} has a pull request without a thread")
        else:
            raise StateError(f"task {task_id} has no child thread ID")
        normalized["tasks"][task_id] = normalized_task
    return normalized


def validate_creation(task_id: str, creation: object) -> dict:
    if not isinstance(creation, dict):
        raise StateError(f"task {task_id} has invalid creation state")
    status = creation.get("status")
    client_thread_id = creation.get("client_thread_id")
    if status == "reserved" and client_thread_id is None:
        return {"status": status}
    if status == "pending" and isinstance(client_thread_id, str) and client_thread_id:
        return {"status": status, "client_thread_id": client_thread_id}
    raise StateError(f"task {task_id} has invalid creation state")


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


def load_merges(path: Path, sessions: dict, repository: str) -> dict:
    if not path.exists():
        return {"version": MERGES_VERSION, "pull_requests": {}}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(f"could not read merges at {path}: {error}") from error
    if not isinstance(data, dict) or data.get("version") != MERGES_VERSION:
        raise StateError("unsupported merges version")
    pull_requests = data.get("pull_requests")
    if not isinstance(pull_requests, dict):
        raise StateError("merges must contain a pull_requests object")

    normalized = {"version": MERGES_VERSION, "pull_requests": {}}
    task_ids = set()
    for number, record in pull_requests.items():
        if not isinstance(number, str) or not PULL_REQUEST_NUMBER.fullmatch(number):
            raise StateError("merges contain an invalid pull request number")
        if not isinstance(record, dict):
            raise StateError(f"merge record for PR {number} must be an object")
        task_id = record.get("task_id")
        merge_commit = record.get("merge_commit")
        parent_notification = record.get("parent_notification")
        local_notification = record.get("local_notification")
        if not isinstance(task_id, str) or not task_id:
            raise StateError(f"merge record for PR {number} has no task ID")
        if task_id in task_ids:
            raise StateError(f"multiple merge records refer to task {task_id}")
        if not isinstance(merge_commit, str) or not merge_commit:
            raise StateError(f"merge record for PR {number} has no merge commit")
        if parent_notification not in ("pending", "delivered"):
            raise StateError(
                f"merge record for PR {number} has invalid parent notification"
            )
        if local_notification not in ("not_sent", "sent"):
            raise StateError(
                f"merge record for PR {number} has invalid local notification"
            )

        task = sessions["tasks"].get(task_id)
        pull_request = task.get("pull_request") if task else None
        expected = {"repository": repository, "number": int(number)}
        if pull_request != expected:
            raise StateError(
                f"merge record for PR {number} does not match the session mapping"
            )
        task_ids.add(task_id)
        normalized["pull_requests"][number] = {
            "task_id": task_id,
            "merge_commit": merge_commit,
            "parent_notification": parent_notification,
            "local_notification": local_notification,
        }
    return normalized


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


def reserve_session(orchestration_id: str, task_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        if not task_id:
            raise StateError("task ID must not be empty")
        if task_id in sessions["tasks"]:
            raise StateError(f"task {task_id} already has session creation state")
        sessions["tasks"][task_id] = {"creation": {"status": "reserved"}}
        write_sessions(path, sessions)
        return sessions


def record_pending(orchestration_id: str, task_id: str, client_thread_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        task = sessions["tasks"].get(task_id)
        if not client_thread_id:
            raise StateError("client thread ID must not be empty")
        pending = {"status": "pending", "client_thread_id": client_thread_id}
        if task == {"creation": pending}:
            return sessions
        if task != {"creation": {"status": "reserved"}}:
            raise StateError(f"task {task_id} has no matching session reservation")
        task["creation"] = pending
        write_sessions(path, sessions)
        return sessions


def release_reservation(orchestration_id: str, task_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        if sessions["tasks"].get(task_id) != {"creation": {"status": "reserved"}}:
            raise StateError(f"task {task_id} has no releasable session reservation")
        del sessions["tasks"][task_id]
        write_sessions(path, sessions)
        return sessions


def record_session(orchestration_id: str, task_id: str, child_thread_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(path, context["parent_thread_id"])
        existing = sessions["tasks"].get(task_id)
        if existing and "child_thread_id" in existing:
            if existing["child_thread_id"] != child_thread_id:
                raise StateError(
                    f"task {task_id} is already associated with another thread"
                )
            return sessions
        if not task_id or not child_thread_id:
            raise StateError("task ID and child thread ID must not be empty")
        if not existing or "creation" not in existing:
            raise StateError(f"task {task_id} has no session reservation")
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
        if task is None or "child_thread_id" not in task:
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
    merges = load_merges(Path(context["merges_path"]), sessions, context["repository"])
    tasks = load_tasks(tasks_path)
    completed_from_merges = {
        record["task_id"] for record in merges["pull_requests"].values()
    }
    completed_additional = set(completed_ids)
    completed = completed_from_merges | completed_additional
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
        "completed_from_merges": sorted(completed_from_merges),
        "completed_additional": sorted(completed_additional),
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

    reservation = commands.add_parser("reserve-session")
    reservation.add_argument("orchestration_id")
    reservation.add_argument("--task-id", required=True)

    pending = commands.add_parser("record-pending")
    pending.add_argument("orchestration_id")
    pending.add_argument("--task-id", required=True)
    pending.add_argument("--client-thread-id", required=True)

    release = commands.add_parser("release-reservation")
    release.add_argument("orchestration_id")
    release.add_argument("--task-id", required=True)

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
            output["merges"] = load_merges(
                Path(output["merges_path"]), output["sessions"], output["repository"]
            )
            output["completed_from_merges"] = sorted(
                record["task_id"]
                for record in output["merges"]["pull_requests"].values()
            )
        elif arguments.command == "plan":
            output = plan(
                arguments.orchestration_id,
                arguments.tasks,
                arguments.completed,
                arguments.max_parallelism,
            )
        elif arguments.command == "reserve-session":
            output = reserve_session(arguments.orchestration_id, arguments.task_id)
        elif arguments.command == "record-pending":
            output = record_pending(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.client_thread_id,
            )
        elif arguments.command == "release-reservation":
            output = release_reservation(arguments.orchestration_id, arguments.task_id)
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
