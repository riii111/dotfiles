#!/usr/bin/env python3
"""Persist and render a completion notification outbox entry."""

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path


OUTBOX_VERSION = 1
ORCHESTRATION_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
TASK_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
WORKER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
MERGE_COMMIT = re.compile(r"^[0-9a-fA-F]{7,64}$")


class NotificationError(ValueError):
    pass


def build_notification(
    orchestration_id: str,
    task_id: str,
    repository: str,
    number: int,
    merge_commit: str,
) -> dict:
    if not isinstance(orchestration_id, str) or not ORCHESTRATION_ID.fullmatch(
        orchestration_id
    ):
        raise NotificationError("invalid orchestration ID")
    if not isinstance(task_id, str) or not TASK_ID.fullmatch(task_id):
        raise NotificationError("invalid task ID")
    if not isinstance(repository, str) or not REPOSITORY.fullmatch(repository):
        raise NotificationError("repository must use owner/repository form")
    if not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise NotificationError("pull request number must be positive")
    if not isinstance(merge_commit, str) or not MERGE_COMMIT.fullmatch(merge_commit):
        raise NotificationError("merge commit must be a hexadecimal Git object ID")

    return {
        "orchestration_id": orchestration_id,
        "task_id": task_id,
        "pull_request": {
            "repository": repository.lower(),
            "number": number,
        },
        "merge_commit": merge_commit.lower(),
        "saved": True,
    }


def outbox_path(orchestration_id: str, task_id: str, worker_id: str) -> Path:
    if not ORCHESTRATION_ID.fullmatch(orchestration_id):
        raise NotificationError("invalid orchestration ID")
    if not TASK_ID.fullmatch(task_id):
        raise NotificationError("invalid task ID")
    if not WORKER_ID.fullmatch(worker_id):
        raise NotificationError("invalid worker ID")
    xdg = Path(value) if (value := os.environ.get("XDG_STATE_HOME")) else None
    base = xdg if xdg and xdg.is_absolute() else Path.home() / ".local" / "state"
    return (
        base
        / "codex-task-orchestrator"
        / orchestration_id
        / "workers"
        / task_id
        / f"{worker_id}.completion-notification.json"
    )


def validate_outbox(raw: object) -> dict:
    if not isinstance(raw, dict) or set(raw) != {
        "version",
        "notification",
        "status",
        "submission_id",
    }:
        raise NotificationError("outbox has missing or unknown fields")
    if raw["version"] != OUTBOX_VERSION or isinstance(raw["version"], bool):
        raise NotificationError("unsupported outbox version")
    notification = raw["notification"]
    if not isinstance(notification, dict):
        raise NotificationError("outbox notification must be an object")
    normalized = build_notification(
        notification.get("orchestration_id"),
        notification.get("task_id"),
        notification.get("pull_request", {}).get("repository")
        if isinstance(notification.get("pull_request"), dict)
        else None,
        notification.get("pull_request", {}).get("number")
        if isinstance(notification.get("pull_request"), dict)
        else 0,
        notification.get("merge_commit"),
    )
    if notification != normalized:
        raise NotificationError("outbox notification has missing or unknown fields")
    status = raw["status"]
    submission_id = raw["submission_id"]
    if status == "pending" and submission_id is None:
        pass
    elif (
        status == "submitted"
        and isinstance(submission_id, str)
        and submission_id.strip()
    ):
        pass
    else:
        raise NotificationError("outbox delivery state is invalid")
    return {
        "version": OUTBOX_VERSION,
        "notification": normalized,
        "status": status,
        "submission_id": submission_id,
    }


def load_outbox(path: Path) -> dict:
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise NotificationError(f"could not read outbox at {path}: {error}") from error
    return validate_outbox(raw)


def write_outbox(path: Path, outbox: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(outbox, temporary, ensure_ascii=False, indent=2, sort_keys=True)
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
def lock_outbox(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def prepare(path: Path, notification: dict) -> dict:
    with lock_outbox(path):
        if path.exists():
            outbox = load_outbox(path)
            if outbox["notification"] != notification:
                raise NotificationError(
                    "outbox already contains a different notification"
                )
            return outbox
        outbox = {
            "version": OUTBOX_VERSION,
            "notification": notification,
            "status": "pending",
            "submission_id": None,
        }
        write_outbox(path, outbox)
        return outbox


def mark_submitted(path: Path, submission_id: str) -> dict:
    if not isinstance(submission_id, str) or not submission_id.strip():
        raise NotificationError("submission ID must not be empty")
    with lock_outbox(path):
        outbox = load_outbox(path)
        existing = outbox["submission_id"]
        if existing is not None and existing != submission_id:
            raise NotificationError("outbox already has another submission ID")
        if existing is None:
            outbox["status"] = "submitted"
            outbox["submission_id"] = submission_id
            write_outbox(path, outbox)
        return outbox


def common_arguments(command: argparse.ArgumentParser) -> None:
    command.add_argument("orchestration_id")
    command.add_argument("--task-id", required=True)
    command.add_argument("--worker-id", required=True)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        description="Manage a completion notification outbox"
    )
    commands = root.add_subparsers(dest="command", required=True)

    prepare_command = commands.add_parser("prepare")
    common_arguments(prepare_command)
    prepare_command.add_argument("--repository", required=True)
    prepare_command.add_argument("--number", type=int, required=True)
    prepare_command.add_argument("--merge-commit", required=True)

    payload_command = commands.add_parser("payload")
    common_arguments(payload_command)

    submitted_command = commands.add_parser("mark-submitted")
    common_arguments(submitted_command)
    submitted_command.add_argument("--submission-id", required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        path = outbox_path(
            arguments.orchestration_id, arguments.task_id, arguments.worker_id
        )
        if arguments.command == "prepare":
            notification = build_notification(
                arguments.orchestration_id,
                arguments.task_id,
                arguments.repository,
                arguments.number,
                arguments.merge_commit,
            )
            outbox = prepare(path, notification)
            output = {
                "path": str(path),
                "status": outbox["status"],
                "submission_id": outbox["submission_id"],
            }
        elif arguments.command == "payload":
            output = load_outbox(path)["notification"]
        else:
            outbox = mark_submitted(path, arguments.submission_id)
            output = {
                "path": str(path),
                "status": outbox["status"],
                "submission_id": outbox["submission_id"],
            }
    except NotificationError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
