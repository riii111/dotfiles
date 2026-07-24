#!/usr/bin/env python3
"""Persist one parent orchestration operation at a time.

                      current plan
                           |
             +-------------+-------------+
             |                           |
             v                           v
  missing Completion Note          launchable task
             |                           |
             v                           v
 [recover_completion_note]       [reserve_session]
             |                           |
             v                           v
  [wait_completion_note]          [create_thread]
             |                           |
       timeout loops here                 v
             |                    [verify_thread]
        Note saved                        |
             |                           v
             +-----> current plan  [record_session]
                                         |
                                         v
                                [set_thread_title]
                                         |
                                         +-----> current plan

  no recovery or launch work --> [complete]
  external operation failure --> [stop] -- retryable --> retry_requested
       confirmed no Thread --> release reservation --> [reserve_session]
  completion notification -----> persist evidence
             |                         |
             +---- keeps active operation and token

The created Thread ID, host, project, and checkout are persisted before
verification or session recording. Every external result carries the current
task-source revision and action token, so stale or contradictory observations
cannot advance the state.
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

import orchestration_state as storage


VERSION = 1
ACTIONS = {
    "recover_completion_note",
    "wait_completion_note",
    "reserve_session",
    "create_thread",
    "verify_thread",
    "record_session",
    "set_thread_title",
    "complete",
    "stop",
}
LAUNCH_STATUSES = {"selected", "reserved", "created", "verified", "recorded"}
WAIT_OUTCOMES = {"timed_out", "completed", "needs_attention", "failed"}
EVENT_FIELDS = {
    "completion_notified": {
        "type",
        "action_token",
        "source_revision",
        "notification",
        "observed_merge_commit",
    },
    "completion_note_observed": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
    },
    "completion_recovery_requested": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "child_thread_id",
        "turn_id",
        "wait_cursor",
    },
    "completion_waited": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "turn_id",
        "outcome",
        "wait_cursor",
    },
    "session_reserved": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
    },
    "thread_created": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "repository",
        "thread_id",
        "host_id",
        "project_id",
        "checkout",
    },
    "thread_verified": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "repository",
        "thread_id",
        "host_id",
        "project_id",
        "checkout",
        "verified",
    },
    "session_recorded": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "thread_id",
    },
    "thread_title_set": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
        "thread_id",
        "title",
    },
    "operation_failed": {
        "type",
        "action_token",
        "source_revision",
        "operation",
        "message",
        "retryable",
    },
    "retry_requested": {
        "type",
        "action_token",
        "source_revision",
    },
    "reservation_released": {
        "type",
        "action_token",
        "source_revision",
        "task_id",
    },
}
ACTION_EVENTS = {
    "recover_completion_note": (
        "completion_note_observed",
        "completion_recovery_requested",
        "operation_failed",
    ),
    "wait_completion_note": (
        "completion_note_observed",
        "completion_waited",
        "operation_failed",
    ),
    "reserve_session": ("session_reserved", "operation_failed"),
    "create_thread": ("thread_created", "operation_failed"),
    "verify_thread": ("thread_verified", "operation_failed"),
    "record_session": ("session_recorded", "operation_failed"),
    "set_thread_title": ("thread_title_set", "operation_failed"),
    "stop": ("retry_requested", "reservation_released"),
}
ROOT_FIELDS = {
    "version",
    "cycle",
    "sequence",
    "source_revision",
    "tasks",
    "completed",
    "maximum_parallelism",
    "policy",
    "notifications",
    "recovery",
    "launch",
    "launch_history",
    "stop",
    "last_event",
}
THREAD_FIELDS = {"thread_id", "host_id", "project_id", "checkout"}
MERGE_COMMIT = re.compile(r"^[0-9a-fA-F]{7,64}$")
NOTIFICATION_FIELDS = {
    "orchestration_id",
    "task_id",
    "pull_request",
    "merge_commit",
    "saved",
}


class TransitionError(ValueError):
    pass


def transition_path(orchestration_id: str) -> Path:
    if not storage.ORCHESTRATION_ID.fullmatch(orchestration_id):
        raise TransitionError("invalid orchestration ID")
    return storage.state_path(orchestration_id).with_name(
        "orchestration-transition.json"
    )


def require_object(value: object, name: str, fields: set[str]) -> dict:
    if not isinstance(value, dict) or set(value) != fields:
        raise TransitionError(f"{name} has missing or unknown fields")
    return value


def require_string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise TransitionError(f"{name} must be a non-empty string")
    return value


def require_optional_string(value: object, name: str) -> str | None:
    if value is not None and (not isinstance(value, str) or not value):
        raise TransitionError(f"{name} must be a non-empty string or null")
    return value


def require_integer(value: object, name: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise TransitionError(f"{name} must be an integer of at least {minimum}")
    return value


def canonical_tasks(tasks: dict[str, dict]) -> list[dict]:
    return [
        {
            "id": task_id,
            "dependencies": list(task["dependencies"]),
            "order": task["order"],
        }
        for task_id, task in tasks.items()
    ]


def tasks_from_state(tasks: object) -> dict[str, dict]:
    try:
        return storage.normalize_tasks({"tasks": tasks})
    except storage.StateError as error:
        raise TransitionError(str(error)) from error


def normalize_thread(value: object) -> dict:
    thread = require_object(value, "thread state", THREAD_FIELDS)
    return {
        field: require_string(thread[field], f"thread.{field}")
        for field in THREAD_FIELDS
    }


def normalize_notification(value: object, orchestration_id: str | None = None) -> dict:
    notification = require_object(value, "completion notification", NOTIFICATION_FIELDS)
    if (
        orchestration_id is not None
        and notification["orchestration_id"] != orchestration_id
    ):
        raise TransitionError(
            "completion notification belongs to another orchestration"
        )
    merge_commit = require_string(
        notification["merge_commit"], "notification.merge_commit"
    )
    if not MERGE_COMMIT.fullmatch(merge_commit):
        raise TransitionError("notification merge commit is not a Git object ID")
    if notification["saved"] is not True:
        raise TransitionError("completion notification is not saved")
    pull_request_value = require_object(
        notification["pull_request"],
        "notification.pull_request",
        {"repository", "number"},
    )
    try:
        pull_request = storage.validate_pull_request(pull_request_value)
    except storage.StateError as error:
        raise TransitionError(str(error)) from error
    return {
        "orchestration_id": require_string(
            notification["orchestration_id"], "notification.orchestration_id"
        ),
        "task_id": require_string(notification["task_id"], "notification.task_id"),
        "pull_request": pull_request,
        "merge_commit": merge_commit.lower(),
        "saved": True,
    }


def normalize_recovery(value: object) -> dict | None:
    if value is None:
        return None
    recovery = require_object(
        value,
        "recovery state",
        {
            "task_id",
            "child_thread_id",
            "pull_request",
            "status",
            "turn_id",
            "wait_cursor",
        },
    )
    status = recovery["status"]
    if status not in {"pending", "waiting"}:
        raise TransitionError("unknown recovery status")
    pull_request = storage.validate_pull_request(recovery["pull_request"])
    turn_id = require_optional_string(recovery["turn_id"], "recovery.turn_id")
    if status == "waiting" and turn_id is None:
        raise TransitionError("waiting recovery has no turn ID")
    if status == "pending" and (
        turn_id is not None or recovery["wait_cursor"] is not None
    ):
        raise TransitionError("pending recovery contains wait state")
    return {
        "task_id": require_string(recovery["task_id"], "recovery.task_id"),
        "child_thread_id": require_string(
            recovery["child_thread_id"], "recovery.child_thread_id"
        ),
        "pull_request": pull_request,
        "status": status,
        "turn_id": turn_id,
        "wait_cursor": require_optional_string(
            recovery["wait_cursor"], "recovery.wait_cursor"
        ),
    }


def normalize_launch(value: object) -> dict | None:
    if value is None:
        return None
    launch = require_object(
        value,
        "launch state",
        {
            "task_id",
            "status",
            "dependency_completion_notes",
            "thread",
        },
    )
    status = launch["status"]
    if status not in LAUNCH_STATUSES:
        raise TransitionError("unknown launch status")
    notes = launch["dependency_completion_notes"]
    if not isinstance(notes, dict):
        raise TransitionError("dependency completion notes must be an object")
    thread = launch["thread"]
    if status in {"created", "verified", "recorded"}:
        thread = normalize_thread(thread)
    elif thread is not None:
        raise TransitionError("launch has thread data before creation")
    return {
        "task_id": require_string(launch["task_id"], "launch.task_id"),
        "status": status,
        "dependency_completion_notes": notes,
        "thread": thread,
    }


def validate_dependency_notes(notes: dict, dependencies: set[str]) -> None:
    if set(notes) - dependencies:
        raise TransitionError("dependency completion notes contain a non-dependency")
    for task_id, note in notes.items():
        if (
            not isinstance(task_id, str)
            or not isinstance(note, dict)
            or set(note) - set(storage.HANDOFF_NOTE_FIELDS)
            or any(not isinstance(value, str) or not value for value in note.values())
        ):
            raise TransitionError("dependency completion notes are invalid")


def normalize_stop(value: object) -> dict | None:
    if value is None:
        return None
    stop = require_object(
        value,
        "stop state",
        {"operation", "message", "retryable"},
    )
    operation = require_string(stop["operation"], "stop.operation")
    if operation not in ACTIONS - {"complete", "stop"}:
        raise TransitionError("stop contains an unknown operation")
    if type(stop["retryable"]) is not bool:
        raise TransitionError("stop.retryable must be a boolean")
    return {
        "operation": operation,
        "message": require_string(stop["message"], "stop.message"),
        "retryable": stop["retryable"],
    }


def normalize_last_event(value: object) -> dict | None:
    if value is None:
        return None
    event = require_object(value, "last event", {"action_token", "digest"})
    return {
        "action_token": require_string(event["action_token"], "last action token"),
        "digest": require_string(event["digest"], "last event digest"),
    }


def normalize_state(raw: object) -> dict:
    state = require_object(raw, "orchestration transition state", ROOT_FIELDS)
    version = require_integer(state["version"], "version", 1)
    if version != VERSION:
        raise TransitionError("unsupported orchestration transition version")
    task_map = tasks_from_state(state["tasks"])
    tasks = canonical_tasks(task_map)
    task_ids = {task["id"] for task in tasks}
    completed = state["completed"]
    if (
        not isinstance(completed, list)
        or any(not isinstance(task_id, str) or not task_id for task_id in completed)
        or len(completed) != len(set(completed))
        or not set(completed) <= task_ids
    ):
        raise TransitionError("completed tasks are invalid")
    launch_history = state["launch_history"]
    if not isinstance(launch_history, list):
        raise TransitionError("launch history must be an array")
    normalized_history = []
    for item in launch_history:
        history = require_object(item, "launch history entry", {"task_id", "thread"})
        normalized_history.append(
            {
                "task_id": require_string(history["task_id"], "history.task_id"),
                "thread": normalize_thread(history["thread"]),
            }
        )
    notifications = state["notifications"]
    if not isinstance(notifications, dict):
        raise TransitionError("completion notifications must be an object")
    normalized_notifications = {}
    for task_id, notification in notifications.items():
        normalized_notification = normalize_notification(notification)
        if (
            not isinstance(task_id, str)
            or task_id != normalized_notification["task_id"]
        ):
            raise TransitionError("completion notification key does not match its task")
        normalized_notifications[task_id] = normalized_notification
    normalized = {
        "version": VERSION,
        "cycle": require_integer(state["cycle"], "cycle", 1),
        "sequence": require_integer(state["sequence"], "sequence"),
        "source_revision": require_string(state["source_revision"], "source revision"),
        "tasks": tasks,
        "completed": sorted(completed),
        "maximum_parallelism": require_integer(
            state["maximum_parallelism"], "maximum parallelism", 1
        ),
        "policy": state["policy"],
        "notifications": normalized_notifications,
        "recovery": normalize_recovery(state["recovery"]),
        "launch": normalize_launch(state["launch"]),
        "launch_history": normalized_history,
        "stop": normalize_stop(state["stop"]),
        "last_event": normalize_last_event(state["last_event"]),
    }
    if normalized["recovery"] and normalized["launch"]:
        raise TransitionError("recovery and launch states cannot both be active")
    if normalized["policy"] not in {"manual", "auto"}:
        raise TransitionError("unknown completion policy")
    if not set(normalized_notifications) <= task_ids:
        raise TransitionError(
            "completion notification task is absent from the current task source"
        )
    if not set(normalized_notifications) <= set(normalized["completed"]):
        raise TransitionError("completion notification task is not completed")
    recovery = normalized["recovery"]
    launch = normalized["launch"]
    if recovery and recovery["task_id"] not in task_ids:
        raise TransitionError("recovery task is absent from the current task source")
    if launch:
        if launch["task_id"] not in task_ids:
            raise TransitionError("launch task is absent from the current task source")
        dependencies = set(task_map[launch["task_id"]]["dependencies"])
        validate_dependency_notes(launch["dependency_completion_notes"], dependencies)
    history_task_ids = [entry["task_id"] for entry in normalized_history]
    if not set(history_task_ids) <= task_ids or len(history_task_ids) != len(
        set(history_task_ids)
    ):
        raise TransitionError("launch history tasks are invalid")
    return normalized


def initial_state(
    source_revision: str,
    tasks: dict[str, dict],
    completed: list[str],
    maximum_parallelism: int,
    policy: str,
    cycle: int = 1,
) -> dict:
    if set(completed) - tasks.keys():
        raise TransitionError("completed tasks are absent from the current task source")
    return normalize_state(
        {
            "version": VERSION,
            "cycle": cycle,
            "sequence": 0,
            "source_revision": require_string(source_revision, "source revision"),
            "tasks": canonical_tasks(tasks),
            "completed": sorted(set(completed)),
            "maximum_parallelism": maximum_parallelism,
            "policy": policy,
            "notifications": {},
            "recovery": None,
            "launch": None,
            "launch_history": [],
            "stop": None,
            "last_event": None,
        }
    )


def load_state(path: Path) -> dict:
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(
            f"could not read orchestration transition state at {path}: {error}"
        ) from error
    return normalize_state(raw)


def write_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(state, temporary, ensure_ascii=False, indent=2, sort_keys=True)
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        temporary_path.chmod(0o600)
        os.replace(temporary_path, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()


@contextmanager
def lock_state(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def current_plan(orchestration_id: str, state: dict) -> dict:
    try:
        return storage.plan_tasks(
            orchestration_id,
            tasks_from_state(state["tasks"]),
            state["completed"],
            state["maximum_parallelism"],
        )
    except storage.StateError as error:
        raise TransitionError(str(error)) from error


def validate_external_state(orchestration_id: str, state: dict) -> None:
    sessions = load_sessions(orchestration_id)
    for notification in state["notifications"].values():
        validate_completion_notification(
            orchestration_id,
            state,
            {
                "notification": notification,
                "observed_merge_commit": notification["merge_commit"],
            },
        )
    recovery = state["recovery"]
    if recovery:
        task = sessions["tasks"].get(recovery["task_id"])
        if (
            not task
            or task.get("child_thread_id") != recovery["child_thread_id"]
            or task.get("pull_request") != recovery["pull_request"]
        ):
            raise TransitionError("recovery state does not match the session mapping")

    launch = state["launch"]
    if launch:
        task = sessions["tasks"].get(launch["task_id"])
        if launch["status"] == "selected":
            if task not in (None, storage.reserved_session()):
                raise TransitionError(
                    "selected launch conflicts with the session mapping"
                )
        elif launch["status"] in {"reserved", "created"}:
            if task != storage.reserved_session():
                raise TransitionError("unrecorded launch lost its session reservation")
        elif launch["status"] == "verified":
            # record-session may persist before its result event reaches this state.
            thread_id = launch["thread"]["thread_id"]
            if task != storage.reserved_session() and (
                not task or task.get("child_thread_id") != thread_id
            ):
                raise TransitionError(
                    "verified launch conflicts with the session mapping"
                )
        elif not task or task.get("child_thread_id") != launch["thread"]["thread_id"]:
            raise TransitionError("recorded launch does not match the session mapping")

    for history in state["launch_history"]:
        task = sessions["tasks"].get(history["task_id"])
        if not task or task.get("child_thread_id") != history["thread"]["thread_id"]:
            raise TransitionError("launch history does not match the session mapping")


def materialize_next(orchestration_id: str, state: dict) -> tuple[dict, dict]:
    validate_external_state(orchestration_id, state)
    if state["stop"] or state["recovery"] or state["launch"]:
        return state, current_plan(orchestration_id, state)
    plan = current_plan(orchestration_id, state)
    if plan["resume_completion_notes"]:
        request = plan["resume_completion_notes"][0]
        state["recovery"] = {
            **request,
            "status": "pending",
            "turn_id": None,
            "wait_cursor": None,
        }
        state["sequence"] += 1
    elif plan["selected"]:
        task_id = plan["selected"][0]
        state["launch"] = {
            "task_id": task_id,
            "status": "selected",
            "dependency_completion_notes": plan["dependency_completion_notes"].get(
                task_id, {}
            ),
            "thread": None,
        }
        state["sequence"] += 1
    return state, plan


def action_name(state: dict) -> str:
    if state["stop"]:
        return "stop"
    if state["recovery"]:
        return (
            "recover_completion_note"
            if state["recovery"]["status"] == "pending"
            else "wait_completion_note"
        )
    if state["launch"]:
        return {
            "selected": "reserve_session",
            "reserved": "create_thread",
            "created": "verify_thread",
            "verified": "record_session",
            "recorded": "set_thread_title",
        }[state["launch"]["status"]]
    return "complete"


def action_token(state: dict, action: str) -> str:
    task_id = ""
    if state["recovery"]:
        task_id = state["recovery"]["task_id"]
    elif state["launch"]:
        task_id = state["launch"]["task_id"]
    payload = ":".join(
        (
            str(state["cycle"]),
            str(state["sequence"]),
            state["source_revision"],
            action,
            task_id,
        )
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def action_details(state: dict, action: str, plan: dict) -> dict:
    if action in {"recover_completion_note", "wait_completion_note"}:
        return dict(state["recovery"])
    if action in {
        "reserve_session",
        "create_thread",
        "verify_thread",
        "record_session",
        "set_thread_title",
    }:
        return dict(state["launch"])
    if action == "stop":
        details = dict(state["stop"])
        if state["launch_history"]:
            details["launched"] = list(state["launch_history"])
        if state["recovery"]:
            details["task_id"] = state["recovery"]["task_id"]
        elif state["launch"]:
            details["task_id"] = state["launch"]["task_id"]
            if state["launch"]["thread"]:
                details["thread"] = dict(state["launch"]["thread"])
        return details
    return {
        "launched": list(state["launch_history"]),
        **{
            key: plan[key]
            for key in (
                "completed",
                "launched_uncompleted",
                "waiting_dependencies",
                "waiting_completion_notes",
                "capacity_deferred",
            )
        },
    }


def event_schemas(action: str, state: dict) -> dict:
    events = [*ACTION_EVENTS.get(action, ()), "completion_notified"]
    if action == "stop":
        if (
            state["stop"]["operation"] == "create_thread"
            or not state["stop"]["retryable"]
        ):
            events.remove("retry_requested")
        if (
            state["stop"]["operation"] != "create_thread"
            or not state["launch"]
            or state["launch"]["status"] != "reserved"
        ):
            events.remove("reservation_released")
    return {event: sorted(EVENT_FIELDS[event]) for event in events}


def output(orchestration_id: str, state: dict, plan: dict) -> dict:
    action = action_name(state)
    return {
        "action": action,
        "action_token": action_token(state, action),
        "allowed_events": event_schemas(action, state),
        "cycle": state["cycle"],
        "details": action_details(state, action, plan),
        "path": str(transition_path(orchestration_id)),
        "policy": state["policy"],
        "source_revision": state["source_revision"],
    }


def event_digest(event: dict) -> str:
    return hashlib.sha256(
        json.dumps(event, ensure_ascii=False, sort_keys=True).encode()
    ).hexdigest()


def require_matching_event(state: dict, event: object, action: str) -> tuple[dict, str]:
    if not isinstance(event, dict) or not isinstance(event.get("type"), str):
        raise TransitionError("event must be an object with a type")
    event_type = event["type"]
    if event_type not in EVENT_FIELDS:
        raise TransitionError("unknown orchestration event")
    if set(event) != EVENT_FIELDS[event_type]:
        raise TransitionError(f"event {event_type} has missing or unknown fields")
    if event["source_revision"] != state["source_revision"]:
        raise TransitionError("event is based on a stale task source")
    token = action_token(state, action)
    event_token = require_string(event["action_token"], "event.action_token")
    # Completion notifications are asynchronous evidence, not action results.
    if event_type != "completion_notified" and event_token != token:
        raise TransitionError("event is based on a stale external observation")
    if event_type not in event_schemas(action, state):
        raise TransitionError(f"event {event_type} is invalid for action {action}")
    return event, token


def require_task(event: dict, task_id: str) -> None:
    if event.get("task_id") != task_id:
        raise TransitionError("event task does not match the current operation")


def load_sessions(orchestration_id: str) -> dict:
    context = storage.load_orchestration(orchestration_id)
    return storage.load_sessions(
        Path(context["sessions_path"]),
        context["parent_thread_id"],
        context["pull_request_repositories"],
    )


def validate_thread_repository(orchestration_id: str, event: dict) -> None:
    repository = require_string(event["repository"], "event.repository")
    context = storage.load_orchestration(orchestration_id)
    if repository not in context["pull_request_repositories"]:
        raise TransitionError("thread repository is not allowed by the orchestration")


def validate_completion_notification(
    orchestration_id: str,
    state: dict,
    event: dict,
) -> dict:
    notification = normalize_notification(event["notification"], orchestration_id)
    task_id = notification["task_id"]
    if task_id not in tasks_from_state(state["tasks"]):
        raise TransitionError(
            "completion notification task is absent from the task source"
        )
    observed_merge_commit = require_string(
        event["observed_merge_commit"], "event.observed_merge_commit"
    ).lower()
    if not MERGE_COMMIT.fullmatch(observed_merge_commit):
        raise TransitionError("observed merge commit is not a Git object ID")
    if observed_merge_commit != notification["merge_commit"]:
        raise TransitionError(
            "completion notification does not match the observed merge"
        )

    sessions = load_sessions(orchestration_id)
    task = sessions["tasks"].get(task_id)
    if (
        not task
        or "child_thread_id" not in task
        or task.get("pull_request") != notification["pull_request"]
    ):
        raise TransitionError(
            "completion notification does not match the session mapping"
        )
    try:
        note = storage.completion_note(orchestration_id, task_id)
    except storage.StateError as error:
        raise TransitionError(str(error)) from error
    if not note["saved"]:
        raise TransitionError("completion notification has no saved Completion Note")
    return notification


def reduce_event(orchestration_id: str, state: dict, event: dict) -> dict:
    action = action_name(state)
    event, token = require_matching_event(state, event, action)
    event_type = event["type"]
    if event_type == "completion_notified":
        notification = validate_completion_notification(orchestration_id, state, event)
        task_id = notification["task_id"]
        existing = state["notifications"].get(task_id)
        if existing is not None and existing != notification:
            raise TransitionError("task already has another completion notification")
        state["notifications"][task_id] = notification
        state["completed"] = sorted({*state["completed"], task_id})
    elif event_type == "operation_failed":
        if event["operation"] != action:
            raise TransitionError("failed operation does not match the current action")
        if type(event["retryable"]) is not bool:
            raise TransitionError("event.retryable must be a boolean")
        if action == "create_thread" and event["retryable"]:
            raise TransitionError("thread creation failures are not directly retryable")
        state["stop"] = {
            "operation": action,
            "message": require_string(event["message"], "event.message"),
            "retryable": event["retryable"],
        }
    elif event_type == "retry_requested":
        state["stop"] = None
    elif event_type == "reservation_released":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        if (
            state["stop"]["operation"] != "create_thread"
            or launch["status"] != "reserved"
        ):
            raise TransitionError(
                "reservation release does not match an uncertain thread creation"
            )
        sessions = load_sessions(orchestration_id)
        if launch["task_id"] in sessions["tasks"]:
            raise TransitionError("session reservation was not released")
        state["stop"] = None
        launch["status"] = "selected"
    elif event_type == "completion_note_observed":
        recovery = state["recovery"]
        require_task(event, recovery["task_id"])
        try:
            note = storage.completion_note(orchestration_id, recovery["task_id"])
        except storage.StateError as error:
            raise TransitionError(str(error)) from error
        if not note["saved"]:
            raise TransitionError("completion note observation is not saved")
        state["recovery"] = None
    elif event_type == "completion_recovery_requested":
        recovery = state["recovery"]
        require_task(event, recovery["task_id"])
        if event["child_thread_id"] != recovery["child_thread_id"]:
            raise TransitionError("recovery event has another child thread")
        recovery.update(
            status="waiting",
            turn_id=require_string(event["turn_id"], "event.turn_id"),
            wait_cursor=require_optional_string(
                event["wait_cursor"], "event.wait_cursor"
            ),
        )
    elif event_type == "completion_waited":
        recovery = state["recovery"]
        require_task(event, recovery["task_id"])
        if event["turn_id"] != recovery["turn_id"]:
            raise TransitionError("wait event has another turn ID")
        outcome = event["outcome"]
        if outcome not in WAIT_OUTCOMES:
            raise TransitionError("unknown wait outcome")
        recovery["wait_cursor"] = require_optional_string(
            event["wait_cursor"], "event.wait_cursor"
        )
        if outcome == "completed":
            try:
                note = storage.completion_note(orchestration_id, recovery["task_id"])
            except storage.StateError as error:
                raise TransitionError(str(error)) from error
            if not note["saved"]:
                raise TransitionError(
                    "completion wait finished before the note was saved"
                )
            state["recovery"] = None
        elif outcome in {"needs_attention", "failed"}:
            state["stop"] = {
                "operation": action,
                "message": f"completion note wait {outcome.replace('_', ' ')}",
                "retryable": outcome == "needs_attention",
            }
    elif event_type == "session_reserved":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        sessions = load_sessions(orchestration_id)
        if sessions["tasks"].get(launch["task_id"]) != storage.reserved_session():
            raise TransitionError("session reservation was not persisted")
        launch["status"] = "reserved"
    elif event_type == "thread_created":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        validate_thread_repository(orchestration_id, event)
        launch["thread"] = {
            field: require_string(event[field], f"event.{field}")
            for field in THREAD_FIELDS
        }
        launch["status"] = "created"
    elif event_type == "thread_verified":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        validate_thread_repository(orchestration_id, event)
        if type(event["verified"]) is not bool or not event["verified"]:
            raise TransitionError("thread verification must be true")
        observed = {field: event[field] for field in THREAD_FIELDS}
        if observed != launch["thread"]:
            raise TransitionError("verified thread does not match the created thread")
        launch["status"] = "verified"
    elif event_type == "session_recorded":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        if event["thread_id"] != launch["thread"]["thread_id"]:
            raise TransitionError("recorded session has another thread ID")
        sessions = load_sessions(orchestration_id)
        task = sessions["tasks"].get(launch["task_id"])
        if not task or task.get("child_thread_id") != event["thread_id"]:
            raise TransitionError("child thread ID was not persisted")
        launch["status"] = "recorded"
    elif event_type == "thread_title_set":
        launch = state["launch"]
        require_task(event, launch["task_id"])
        if event["thread_id"] != launch["thread"]["thread_id"]:
            raise TransitionError("title event has another thread ID")
        title = require_string(event["title"], "event.title")
        if not title.startswith(f"[{launch['task_id']}] "):
            raise TransitionError("thread title does not start with the task ID")
        state["launch_history"].append(
            {"task_id": launch["task_id"], "thread": launch["thread"]}
        )
        state["launch"] = None
    else:
        raise AssertionError("validated event was not reduced")
    # Notifications must not invalidate an in-flight external operation token.
    if event_type != "completion_notified":
        state["sequence"] += 1
        state["last_event"] = {
            "action_token": token,
            "digest": event_digest(event),
        }
    return normalize_state(state)


def read_event(path: Path) -> dict:
    try:
        event = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(f"could not read orchestration event: {error}") from error
    if not isinstance(event, dict):
        raise TransitionError("orchestration event must be an object")
    return event


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Return one parent orchestration action")
    commands = root.add_subparsers(dest="command", required=True)

    state_path_command = commands.add_parser("state-path")
    state_path_command.add_argument("orchestration_id")

    initialize = commands.add_parser("init")
    initialize.add_argument("orchestration_id")
    initialize.add_argument("--tasks", type=Path, required=True)
    initialize.add_argument("--completed", action="append", default=[])
    initialize.add_argument("--max-parallelism", type=int, required=True)
    initialize.add_argument("--policy", choices=("manual", "auto"), required=True)
    initialize.add_argument("--source-revision", required=True)

    for name in ("next", "apply-event"):
        command = commands.add_parser(name)
        command.add_argument("orchestration_id")
        command.add_argument("--source-revision", required=True)
        if name == "apply-event":
            command.add_argument("--event-file", type=Path, required=True)
    return root


def same_inputs(
    state: dict,
    source_revision: str,
    tasks: dict[str, dict],
    completed: list[str],
    maximum_parallelism: int,
    policy: str,
) -> bool:
    return (
        state["source_revision"] == source_revision
        and state["tasks"] == canonical_tasks(tasks)
        and state["completed"] == sorted(set(completed))
        and state["maximum_parallelism"] == maximum_parallelism
        and state["policy"] == policy
    )


def completed_inputs(
    orchestration_id: str,
    tasks: dict[str, dict],
    completed: list[str],
    maximum_parallelism: int,
    persisted_completed: list[str] | None = None,
) -> list[str]:
    try:
        plan = storage.plan_tasks(
            orchestration_id,
            tasks,
            completed,
            maximum_parallelism,
        )
    except storage.StateError as error:
        raise TransitionError(str(error)) from error
    if persisted_completed is None:
        return plan["completed"]
    confirmed_notes = set(plan["completed_from_notes"]) & set(persisted_completed)
    return sorted({*completed, *confirmed_notes})


def resolve_init_state(
    orchestration_id: str,
    path: Path,
    tasks: dict[str, dict],
    completed: list[str],
    maximum_parallelism: int,
    policy: str,
    source_revision: str,
) -> dict:
    state = load_state(path) if path.exists() else None
    normalized_completed = completed_inputs(
        orchestration_id,
        tasks,
        completed,
        maximum_parallelism,
        (
            state["completed"]
            if state is not None and action_name(state) != "complete"
            else None
        ),
    )
    if state is None:
        return initial_state(
            source_revision,
            tasks,
            normalized_completed,
            maximum_parallelism,
            policy,
        )
    if same_inputs(
        state,
        source_revision,
        tasks,
        normalized_completed,
        maximum_parallelism,
        policy,
    ):
        return state
    if action_name(state) != "complete":
        raise TransitionError("cycle inputs changed during an active operation")
    validate_external_state(orchestration_id, state)
    return initial_state(
        source_revision,
        tasks,
        normalized_completed,
        maximum_parallelism,
        policy,
        state["cycle"] + 1,
    )


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        path = transition_path(arguments.orchestration_id)
        if arguments.command == "state-path":
            result = {"path": str(path)}
        elif arguments.command == "init":
            try:
                tasks = storage.load_tasks(arguments.tasks)
            except storage.StateError as error:
                raise TransitionError(str(error)) from error
            with lock_state(path):
                state = resolve_init_state(
                    arguments.orchestration_id,
                    path,
                    tasks,
                    arguments.completed,
                    arguments.max_parallelism,
                    arguments.policy,
                    arguments.source_revision,
                )
                state, plan = materialize_next(arguments.orchestration_id, state)
                write_state(path, state)
            result = output(arguments.orchestration_id, state, plan)
        elif arguments.command == "next":
            with lock_state(path):
                state = load_state(path)
                if arguments.source_revision != state["source_revision"]:
                    raise TransitionError("task source revision is stale")
                state, plan = materialize_next(arguments.orchestration_id, state)
                write_state(path, state)
            result = output(arguments.orchestration_id, state, plan)
        else:
            event = read_event(arguments.event_file)
            with lock_state(path):
                state = load_state(path)
                if arguments.source_revision != state["source_revision"]:
                    raise TransitionError("task source revision is stale")
                digest = event_digest(event)
                if (
                    event.get("type") != "completion_notified"
                    and state["last_event"]
                    and event.get("action_token") == state["last_event"]["action_token"]
                ):
                    if digest != state["last_event"]["digest"]:
                        raise TransitionError(
                            "action token was reused with a different event"
                        )
                else:
                    state = reduce_event(arguments.orchestration_id, state, event)
                    write_state(path, state)
                state, plan = materialize_next(arguments.orchestration_id, state)
                write_state(path, state)
            result = output(arguments.orchestration_id, state, plan)
    except (TransitionError, storage.StateError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
