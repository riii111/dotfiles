#!/usr/bin/env python3
"""Advance one task worker lifecycle.

    pr absent
        |
        v
    [implement] --> draft PR
                       |
                       v
              [request_review] <----------------------+
                       |                               |
                       v                               |
                 [wait_review]                         |
                       |                               |
               +-------+--------+                      |
               |                |                      |
               v                v                      |
        [address_review]   review accepted              |
               |                |                      |
               +---- many findings --------------------+
                                |
                                v
                         [verify/checks]
                                |
                    +-----------+-----------+
                    |                       |
               manual: report        auto: mark_ready
                                            |
                                            v
                                         [merge]
                                            |
                                            v
                              [record_completion_note]
                                            |
                                            v
                                        complete

Every bracketed step is one returned action. External work reports an event back
to this script; the reducer writes the resulting state before the next action is
selected.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path


class TransitionError(ValueError):
    pass


PR_STATES = {"absent", "draft", "ready", "merged", "closed"}
REVIEW_STATES = {"absent", "pending", "completed"}
CHECK_STATES = {"not_run", "pending", "failed", "passed"}
POLICIES = {"manual", "auto"}
ROOT_FIELDS = {
    "pr",
    "review",
    "checks",
    "policy",
    "completion_note_saved",
    "head_sha",
    "mergeable",
}
REVIEW_FIELDS = {
    "status",
    "head_sha",
    "applied_head_sha",
    "blocking",
    "non_blocking",
    "thread_id",
    "turn_id",
}
CHECK_FIELDS = {"status", "head_sha"}
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")


def require_object(value: object, name: str, fields: set[str]) -> dict:
    if not isinstance(value, dict) or set(value) != fields:
        raise TransitionError(f"{name} has missing or unknown fields")
    return value


def require_choice(value: object, name: str, choices: set[str]) -> str:
    if not isinstance(value, str) or value not in choices:
        raise TransitionError(f"unknown {name}")
    return value


def require_optional_string(value: object, name: str) -> str | None:
    if value is not None and (not isinstance(value, str) or not value):
        raise TransitionError(f"{name} must be a non-empty string or null")
    return value


def require_count(value: object, name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise TransitionError(f"{name} must be a non-negative integer")
    return value


def load_state(path: Path) -> dict:
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(f"could not read worker state at {path}: {error}") from error
    state = require_object(raw, "worker state", ROOT_FIELDS)
    review = require_object(state["review"], "review state", REVIEW_FIELDS)
    checks = require_object(state["checks"], "checks state", CHECK_FIELDS)

    normalized = {
        "pr": require_choice(state["pr"], "pull request state", PR_STATES),
        "policy": require_choice(state["policy"], "completion policy", POLICIES),
        "completion_note_saved": state["completion_note_saved"],
        "head_sha": require_optional_string(state["head_sha"], "head_sha"),
        "mergeable": state["mergeable"],
        "review": {
            "status": require_choice(
                review["status"], "review state", REVIEW_STATES
            ),
            "head_sha": require_optional_string(
                review["head_sha"], "review.head_sha"
            ),
            "applied_head_sha": require_optional_string(
                review["applied_head_sha"], "review.applied_head_sha"
            ),
            "blocking": require_count(review["blocking"], "review.blocking"),
            "non_blocking": require_count(
                review["non_blocking"], "review.non_blocking"
            ),
            "thread_id": require_optional_string(
                review["thread_id"], "review.thread_id"
            ),
            "turn_id": require_optional_string(review["turn_id"], "review.turn_id"),
        },
        "checks": {
            "status": require_choice(
                checks["status"], "checks state", CHECK_STATES
            ),
            "head_sha": require_optional_string(
                checks["head_sha"], "checks.head_sha"
            ),
        },
    }
    if type(normalized["completion_note_saved"]) is not bool:
        raise TransitionError("completion_note_saved must be a boolean")
    if type(normalized["mergeable"]) is not bool:
        raise TransitionError("mergeable must be a boolean")
    return normalized


def review_action(state: dict) -> str:
    review = state["review"]
    head_sha = state["head_sha"]
    status = review["status"]

    if status == "absent":
        if any(review[field] is not None for field in ("head_sha", "turn_id")):
            raise TransitionError("absent review contains processing state")
        if review["blocking"] or review["non_blocking"]:
            raise TransitionError("absent review contains findings")
        return "request_review"
    if not review["thread_id"]:
        raise TransitionError("active review has no review thread ID")
    if status == "pending":
        if not review["turn_id"]:
            raise TransitionError("pending review has no turn ID")
        return "wait_review"
    if review["turn_id"]:
        raise TransitionError("completed review still has a pending turn ID")
    if not review["head_sha"]:
        raise TransitionError("completed review has no reviewed head SHA")

    findings = review["blocking"] + review["non_blocking"]
    if findings and not review["applied_head_sha"]:
        return "address_review"
    if review["blocking"] or review["non_blocking"] > 2:
        return "request_review"
    accepted_head = review["applied_head_sha"] or review["head_sha"]
    if accepted_head != head_sha:
        raise TransitionError("accepted review does not match the current head")
    return "review_passed"


def checks_action(state: dict) -> str:
    checks = state["checks"]
    match checks["status"]:
        case "not_run" | "failed":
            return "verify"
        case "pending":
            if checks["head_sha"] != state["head_sha"]:
                raise TransitionError("pending checks do not match the current head")
            return "wait_checks"
        case "passed" if checks["head_sha"] == state["head_sha"]:
            return "checks_passed"
        case "passed":
            raise TransitionError("passed checks do not match the current head")
    raise AssertionError("validated checks state was not handled")


def next_action(state: dict) -> str:
    pr = state["pr"]
    policy = state["policy"]
    note_saved = state["completion_note_saved"]

    if pr == "closed":
        raise TransitionError("closed pull request cannot advance")
    if pr != "merged" and note_saved:
        raise TransitionError("an unmerged pull request cannot have a completion note")
    if pr == "merged":
        return "complete" if note_saved else "record_completion_note"
    if pr == "ready" and policy == "manual":
        raise TransitionError("manual policy cannot advance a ready pull request")
    if pr == "absent":
        if state["head_sha"] is not None:
            raise TransitionError("work without a pull request cannot have a head SHA")
        if review_action(state) != "request_review":
            raise TransitionError("work without a pull request has active review state")
        if state["checks"] != {"status": "not_run", "head_sha": None}:
            raise TransitionError("work without a pull request has checks state")
        return "implement"
    if not state["head_sha"]:
        raise TransitionError("tracked pull request has no head SHA")

    match review_action(state):
        case "request_review":
            return "request_review"
        case "wait_review":
            return "wait_review"
        case "address_review":
            return "address_review"
        case "review_passed":
            pass

    match checks_action(state):
        case "verify":
            return "verify"
        case "wait_checks":
            return "wait_checks"
        case "checks_passed" if pr == "draft":
            return "report_manual" if policy == "manual" else "mark_ready"
        case "checks_passed":
            if not state["mergeable"]:
                raise TransitionError("pull request is not mergeable")
            return "merge"
    raise AssertionError("validated worker state was not handled")


def worker_state_path(orchestration_id: str, task_id: str) -> Path:
    if not ID.fullmatch(orchestration_id) or not ID.fullmatch(task_id):
        raise TransitionError("orchestration ID and task ID must be filesystem-safe")
    xdg = Path(value) if (value := os.environ.get("XDG_STATE_HOME")) else None
    base = xdg if xdg and xdg.is_absolute() else Path.home() / ".local" / "state"
    return (
        base
        / "codex-task-orchestrator"
        / orchestration_id
        / "workers"
        / f"{task_id}.json"
    )


def initial_state(policy: str) -> dict:
    return {
        "pr": "absent",
        "head_sha": None,
        "mergeable": True,
        "review": {
            "status": "absent",
            "head_sha": None,
            "applied_head_sha": None,
            "blocking": 0,
            "non_blocking": 0,
            "thread_id": None,
            "turn_id": None,
        },
        "checks": {"status": "not_run", "head_sha": None},
        "policy": require_choice(policy, "completion policy", POLICIES),
        "completion_note_saved": False,
    }


def reduce_state(state: dict, event: dict) -> dict:
    if not isinstance(event, dict) or not isinstance(event.get("type"), str):
        raise TransitionError("event must be an object with a type")
    updated = json.loads(json.dumps(state))
    event_type = event["type"]

    match event_type:
        case "pr_created":
            updated["pr"] = "draft"
            updated["head_sha"] = require_optional_string(
                event.get("head_sha"), "event.head_sha"
            )
            updated["mergeable"] = True
        case "review_requested":
            updated["review"].update(
                status="pending",
                thread_id=require_optional_string(
                    event.get("thread_id"), "event.thread_id"
                ),
                turn_id=require_optional_string(event.get("turn_id"), "event.turn_id"),
                head_sha=None,
                applied_head_sha=None,
                blocking=0,
                non_blocking=0,
            )
        case "review_completed":
            updated["review"].update(
                status="completed",
                head_sha=require_optional_string(
                    event.get("head_sha"), "event.head_sha"
                ),
                applied_head_sha=None,
                blocking=require_count(event.get("blocking"), "event.blocking"),
                non_blocking=require_count(
                    event.get("non_blocking"), "event.non_blocking"
                ),
                turn_id=None,
            )
        case "changes_applied":
            head_sha = require_optional_string(event.get("head_sha"), "event.head_sha")
            updated["head_sha"] = head_sha
            updated["review"]["applied_head_sha"] = head_sha
            updated["checks"] = {"status": "not_run", "head_sha": None}
        case "checks_started":
            updated["checks"] = {
                "status": "pending",
                "head_sha": require_optional_string(
                    event.get("head_sha"), "event.head_sha"
                ),
            }
        case "checks_completed":
            status = require_choice(
                event.get("status"), "checks event state", {"passed", "failed"}
            )
            updated["checks"] = {
                "status": status,
                "head_sha": require_optional_string(
                    event.get("head_sha"), "event.head_sha"
                ),
            }
        case "marked_ready":
            updated["pr"] = "ready"
        case "mergeability_changed":
            if type(event.get("mergeable")) is not bool:
                raise TransitionError("event.mergeable must be a boolean")
            updated["mergeable"] = event["mergeable"]
        case "merged":
            updated["pr"] = "merged"
        case "completion_note_saved":
            updated["completion_note_saved"] = True
        case _:
            raise TransitionError("unknown worker event")
    return load_state_object(updated)


def load_state_object(raw: object) -> dict:
    with tempfile.NamedTemporaryFile(mode="w+", encoding="utf-8") as temporary:
        json.dump(raw, temporary)
        temporary.flush()
        return load_state(Path(temporary.name))


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
        os.replace(temporary_path, path)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Return one next worker action")
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("state-path", "init", "next", "apply-event"):
        command = commands.add_parser(name)
        command.add_argument("orchestration_id")
        command.add_argument("--task-id", required=True)
        if name == "init":
            command.add_argument("--policy", required=True)
        if name == "apply-event":
            command.add_argument("--event-file", type=Path, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        path = worker_state_path(arguments.orchestration_id, arguments.task_id)
        if arguments.command == "state-path":
            output = {"path": str(path)}
        elif arguments.command == "init":
            if path.exists():
                raise TransitionError("worker state already exists")
            state = initial_state(arguments.policy)
            write_state(path, state)
            output = {"path": str(path), "state": state}
        elif arguments.command == "next":
            output = {"action": next_action(load_state(path)), "path": str(path)}
        else:
            try:
                event = json.loads(arguments.event_file.read_text())
            except (OSError, json.JSONDecodeError) as error:
                raise TransitionError(f"could not read worker event: {error}") from error
            state = reduce_state(load_state(path), event)
            write_state(path, state)
            output = {
                "action": next_action(state),
                "path": str(path),
                "state": state,
            }
    except TransitionError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
