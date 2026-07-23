#!/usr/bin/env python3

import argparse
import json
import sys
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
            return "merge"
    raise AssertionError("validated worker state was not handled")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Return one next worker action")
    root.add_argument("--state", type=Path, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        output = {"action": next_action(load_state(arguments.state))}
    except TransitionError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
