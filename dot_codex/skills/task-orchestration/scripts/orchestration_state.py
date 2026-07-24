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


SESSION_VERSION = 1
COMPLETION_NOTES_VERSION = 1
ORCHESTRATION_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
COMPLETION_NOTE_FIELDS = frozenset(
    {"risks", "handoff", "review_learnings", "technical_debt"}
)
HANDOFF_NOTE_FIELDS = ("risks", "handoff")


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


def completion_notes_path(orchestration_id: str) -> Path:
    return state_path(orchestration_id).parent.parent / "completion-notes.json"


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
    pull_request_repositories = orchestration.get(
        "pull_request_repositories", [orchestration["repository"]]
    )
    if (
        not isinstance(pull_request_repositories, list)
        or not pull_request_repositories
        or any(
            not isinstance(repository, str) or not REPOSITORY.fullmatch(repository)
            for repository in pull_request_repositories
        )
        or len(pull_request_repositories)
        != len({repository.lower() for repository in pull_request_repositories})
    ):
        raise StateError(
            "pull_request_repositories must be a non-empty unique owner/repository list"
        )

    return {
        "orchestration_id": orchestration_id,
        "parent_thread_id": orchestration["parent_thread_id"],
        "repository": orchestration["repository"].lower(),
        "task_source": orchestration["task_source"],
        "pull_request_repositories": [
            repository.lower() for repository in pull_request_repositories
        ],
        "sessions_path": str(state_path(orchestration_id)),
        "completion_notes_path": str(completion_notes_path(orchestration_id)),
    }


def empty_sessions(parent_thread_id: str) -> dict:
    return {
        "version": SESSION_VERSION,
        "parent_thread_id": parent_thread_id,
        "tasks": {},
    }


def load_sessions(
    path: Path, parent_thread_id: str, pull_request_repositories: list[str]
) -> dict:
    if not path.exists():
        return empty_sessions(parent_thread_id)
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(f"could not read sessions at {path}: {error}") from error

    version = data.get("version") if isinstance(data, dict) else None
    if type(version) is not int or version != SESSION_VERSION:
        raise StateError("unsupported sessions version")
    if data.get("parent_thread_id") != parent_thread_id or not isinstance(
        data.get("tasks"), dict
    ):
        raise StateError("sessions parent or tasks do not match the orchestration")

    normalized = empty_sessions(parent_thread_id)
    pull_request_tasks = {}
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
                pull_request = validate_pull_request(task["pull_request"])
                if pull_request["repository"] not in pull_request_repositories:
                    raise StateError(
                        f"task {task_id} pull request repository is not allowed"
                    )
                key = (pull_request["repository"], pull_request["number"])
                if key in pull_request_tasks:
                    raise StateError(
                        f"tasks {pull_request_tasks[key]} and {task_id} share a pull request"
                    )
                pull_request_tasks[key] = task_id
                normalized_task["pull_request"] = pull_request
        else:
            normalized_task = {"creation": validate_creation(task_id, creation)}
            if "pull_request" in task:
                raise StateError(f"task {task_id} has a pull request without a thread")
        normalized["tasks"][task_id] = normalized_task
    return normalized


def validate_creation(task_id: str, creation: object) -> dict:
    if creation == {"status": "reserved"}:
        return creation
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
    return {"repository": repository.lower(), "number": number}


def empty_completion_notes() -> dict:
    return {"version": COMPLETION_NOTES_VERSION, "orchestrations": {}}


def validate_completion_note(note: object) -> dict:
    if not isinstance(note, dict):
        raise StateError("completion note must be an object")
    unknown_fields = set(note) - COMPLETION_NOTE_FIELDS
    if unknown_fields:
        raise StateError("completion note contains an unknown field")

    normalized = {}
    for field, value in note.items():
        if not isinstance(value, str) or not value.strip():
            raise StateError(f"completion note {field} must be a non-empty string")
        normalized[field] = value
    return normalized


def load_completion_notes(path: Path) -> dict:
    if not path.exists():
        return empty_completion_notes()
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(
            f"could not read completion notes at {path}: {error}"
        ) from error

    version = data.get("version") if isinstance(data, dict) else None
    if type(version) is not int or version != COMPLETION_NOTES_VERSION:
        raise StateError("unsupported completion notes version")
    orchestrations = data.get("orchestrations")
    if not isinstance(orchestrations, dict):
        raise StateError("completion notes must contain an orchestrations object")

    normalized = empty_completion_notes()
    for orchestration_id, orchestration in orchestrations.items():
        if not isinstance(orchestration_id, str) or not ORCHESTRATION_ID.fullmatch(
            orchestration_id
        ):
            raise StateError("completion notes contain an invalid orchestration ID")
        if not isinstance(orchestration, dict) or set(orchestration) != {"tasks"}:
            raise StateError(
                "completion notes orchestration must contain a tasks object"
            )
        tasks = orchestration["tasks"]
        if not isinstance(tasks, dict):
            raise StateError("completion notes tasks must be an object")
        normalized_tasks = {}
        for task_id, note in tasks.items():
            if not isinstance(task_id, str) or not task_id:
                raise StateError("completion notes contain an invalid task ID")
            normalized_tasks[task_id] = validate_completion_note(note)
        normalized["orchestrations"][orchestration_id] = {"tasks": normalized_tasks}
    return normalized


def load_completion_note_file(path: Path) -> dict:
    try:
        note = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(
            f"could not read completion note at {path}: {error}"
        ) from error
    return validate_completion_note(note)


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


def write_completion_notes(path: Path, completion_notes: dict) -> None:
    write_sessions(path, completion_notes)


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
        sessions = load_sessions(
            path,
            context["parent_thread_id"],
            context["pull_request_repositories"],
        )
        if not task_id:
            raise StateError("task ID must not be empty")
        if task_id in sessions["tasks"]:
            raise StateError(f"task {task_id} already has session creation state")
        sessions["tasks"][task_id] = {"creation": {"status": "reserved"}}
        write_sessions(path, sessions)
        return sessions


def release_reservation(orchestration_id: str, task_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(
            path,
            context["parent_thread_id"],
            context["pull_request_repositories"],
        )
        if sessions["tasks"].get(task_id) != {"creation": {"status": "reserved"}}:
            raise StateError(f"task {task_id} has no releasable session reservation")
        del sessions["tasks"][task_id]
        write_sessions(path, sessions)
        return sessions


def record_session(orchestration_id: str, task_id: str, child_thread_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(
            path,
            context["parent_thread_id"],
            context["pull_request_repositories"],
        )
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
    pull_request = validate_pull_request({"repository": repository, "number": number})
    if pull_request["repository"] not in context["pull_request_repositories"]:
        raise StateError("pull request repository is not allowed by the orchestration")
    path = Path(context["sessions_path"])
    with lock_sessions(path):
        sessions = load_sessions(
            path,
            context["parent_thread_id"],
            context["pull_request_repositories"],
        )
        task = sessions["tasks"].get(task_id)
        if task is None or "child_thread_id" not in task:
            raise StateError(f"task {task_id} has no child session")
        existing = task.get("pull_request")
        if existing and existing != pull_request:
            raise StateError(
                f"task {task_id} is already associated with another pull request"
            )
        if existing == pull_request:
            return sessions
        for other_task_id, other_task in sessions["tasks"].items():
            if (
                other_task_id != task_id
                and other_task.get("pull_request") == pull_request
            ):
                raise StateError(
                    f"pull request is already associated with task {other_task_id}"
                )
        task["pull_request"] = pull_request
        write_sessions(path, sessions)
        return sessions


def record_completion_note(
    orchestration_id: str, task_id: str, note_file: Path
) -> dict:
    context = load_orchestration(orchestration_id)
    note = load_completion_note_file(note_file)
    sessions_path = Path(context["sessions_path"])
    notes_path = Path(context["completion_notes_path"])
    with lock_sessions(sessions_path):
        sessions = load_sessions(
            sessions_path,
            context["parent_thread_id"],
            context["pull_request_repositories"],
        )
        task = sessions["tasks"].get(task_id)
        if task is None or "child_thread_id" not in task:
            raise StateError(f"task {task_id} has no child session")
        if "pull_request" not in task:
            raise StateError(f"task {task_id} has no tracked pull request")
        with lock_sessions(notes_path):
            completion_notes = load_completion_notes(notes_path)
            tasks = completion_notes["orchestrations"].setdefault(
                orchestration_id, {"tasks": {}}
            )["tasks"]
            existing = tasks.get(task_id)
            if existing is not None:
                if existing != note:
                    raise StateError(
                        f"task {task_id} already has a different completion note"
                    )
                return completion_notes
            tasks[task_id] = note
            write_completion_notes(notes_path, completion_notes)
            return completion_notes


def completion_note(orchestration_id: str, task_id: str) -> dict:
    context = load_orchestration(orchestration_id)
    sessions = load_sessions(
        Path(context["sessions_path"]),
        context["parent_thread_id"],
        context["pull_request_repositories"],
    )
    task = sessions["tasks"].get(task_id)
    if task is None or "child_thread_id" not in task:
        raise StateError(f"task {task_id} has no child session")
    if "pull_request" not in task:
        raise StateError(f"task {task_id} has no tracked pull request")

    notes = load_completion_notes(Path(context["completion_notes_path"]))
    note = (
        notes["orchestrations"]
        .get(orchestration_id, {"tasks": {}})["tasks"]
        .get(task_id)
    )
    return {"task_id": task_id, "saved": note is not None, "note": note}


def normalize_tasks(payload: object) -> dict[str, dict]:
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


def load_tasks(path: Path) -> dict[str, dict]:
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise StateError(
            f"could not read normalized tasks at {path}: {error}"
        ) from error
    return normalize_tasks(payload)


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
    return plan_tasks(
        orchestration_id,
        load_tasks(tasks_path),
        completed_ids,
        maximum_parallelism,
    )


def plan_tasks(
    orchestration_id: str,
    tasks: dict[str, dict],
    completed_ids: list[str],
    maximum_parallelism: int,
) -> dict:
    if maximum_parallelism < 1:
        raise StateError("maximum parallelism must be positive")
    context = load_orchestration(orchestration_id)
    sessions = load_sessions(
        Path(context["sessions_path"]),
        context["parent_thread_id"],
        context["pull_request_repositories"],
    )
    completion_notes = load_completion_notes(Path(context["completion_notes_path"]))
    completed_additional = set(completed_ids)
    noted_tasks = set(
        completion_notes["orchestrations"].get(orchestration_id, {"tasks": {}})["tasks"]
    )
    completed = noted_tasks | completed_additional
    unknown_completed = completed - tasks.keys()
    unknown_launched = sessions["tasks"].keys() - tasks.keys()
    unknown_noted = noted_tasks - tasks.keys()
    tracked_tasks = {
        task_id for task_id, task in sessions["tasks"].items() if "pull_request" in task
    }
    orphaned_noted = noted_tasks - tracked_tasks
    if unknown_completed or unknown_launched or unknown_noted:
        raise StateError(
            "completed, launched, or noted tasks are absent from the current task source"
        )
    if orphaned_noted:
        raise StateError("completion notes do not match tracked pull requests")

    missing_completion_notes = completed & tracked_tasks - noted_tasks
    completion_ready = completed - missing_completion_notes

    launched = set(sessions["tasks"])
    active = launched - completed
    available = max(0, maximum_parallelism - len(active))
    ready = [
        task_id
        for task_id, task in tasks.items()
        if task_id not in completed | launched
        and set(task["dependencies"]) <= completion_ready
    ]
    ready.sort(key=lambda task_id: (tasks[task_id]["order"], task_id))
    selected = ready[:available]

    waiting = {
        task_id: sorted(set(task["dependencies"]) - completed)
        for task_id, task in tasks.items()
        if task_id not in completed | launched and set(task["dependencies"]) - completed
    }
    waiting_completion_notes = {
        task_id: sorted(set(task["dependencies"]) & missing_completion_notes)
        for task_id, task in tasks.items()
        if task_id not in completed | launched
        and set(task["dependencies"]) & missing_completion_notes
    }
    resume_completion_notes = [
        {
            "task_id": task_id,
            "child_thread_id": sessions["tasks"][task_id]["child_thread_id"],
            "pull_request": sessions["tasks"][task_id]["pull_request"],
        }
        for task_id in sorted(missing_completion_notes)
    ]
    dependency_completion_notes = {}
    current_notes = completion_notes["orchestrations"].get(
        orchestration_id, {"tasks": {}}
    )["tasks"]
    for task_id in selected:
        notes = {
            dependency: {
                field: current_notes.get(dependency, {})[field]
                for field in HANDOFF_NOTE_FIELDS
                if field in current_notes.get(dependency, {})
            }
            for dependency in tasks[task_id]["dependencies"]
            if any(
                field in current_notes.get(dependency, {})
                for field in HANDOFF_NOTE_FIELDS
            )
        }
        if notes:
            dependency_completion_notes[task_id] = notes
    return {
        "selected": selected,
        "completed": sorted(completed),
        "completed_from_notes": sorted(noted_tasks),
        "completed_additional": sorted(completed_additional),
        "launched_uncompleted": sorted(active),
        "waiting_dependencies": waiting,
        "waiting_completion_notes": waiting_completion_notes,
        "resume_completion_notes": resume_completion_notes,
        "dependency_completion_notes": dependency_completion_notes,
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

    release = commands.add_parser("release-reservation")
    release.add_argument("orchestration_id")
    release.add_argument("--task-id", required=True)

    pull_request = commands.add_parser("record-pr")
    pull_request.add_argument("orchestration_id")
    pull_request.add_argument("--task-id", required=True)
    pull_request.add_argument("--repository", required=True)
    pull_request.add_argument("--number", type=int, required=True)

    completion_note = commands.add_parser("record-completion-note")
    completion_note.add_argument("orchestration_id")
    completion_note.add_argument("--task-id", required=True)
    completion_note.add_argument("--note-file", type=Path, required=True)

    completion_note = commands.add_parser("completion-note")
    completion_note.add_argument("orchestration_id")
    completion_note.add_argument("--task-id", required=True)

    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        if arguments.command == "context":
            output = load_orchestration(arguments.orchestration_id)
            output["sessions"] = load_sessions(
                Path(output["sessions_path"]),
                output["parent_thread_id"],
                output["pull_request_repositories"],
            )
            load_completion_notes(Path(output["completion_notes_path"]))
        elif arguments.command == "plan":
            output = plan(
                arguments.orchestration_id,
                arguments.tasks,
                arguments.completed,
                arguments.max_parallelism,
            )
        elif arguments.command == "reserve-session":
            output = reserve_session(arguments.orchestration_id, arguments.task_id)
        elif arguments.command == "release-reservation":
            output = release_reservation(arguments.orchestration_id, arguments.task_id)
        elif arguments.command == "record-session":
            output = record_session(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.child_thread_id,
            )
        elif arguments.command == "record-completion-note":
            output = record_completion_note(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.note_file,
            )
        elif arguments.command == "completion-note":
            output = completion_note(arguments.orchestration_id, arguments.task_id)
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
