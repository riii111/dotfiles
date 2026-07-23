#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path


class TransitionError(ValueError):
    pass


PR_STATES = {"absent", "draft", "ready", "merged", "closed"}
REVIEW_STATES = {"absent", "pending", "changes_required", "passed"}
CHECK_STATES = {"not_run", "pending", "failed", "passed"}
POLICIES = {"manual", "auto"}


def load_state(path: Path) -> dict:
    try:
        state = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(f"could not read worker state at {path}: {error}") from error
    if not isinstance(state, dict):
        raise TransitionError("worker state must be an object")
    expected = {"pr", "review", "checks", "policy", "completion_note_saved"}
    if set(state) != expected:
        raise TransitionError("worker state has missing or unknown fields")
    if state["pr"] not in PR_STATES:
        raise TransitionError("unknown pull request state")
    if state["review"] not in REVIEW_STATES:
        raise TransitionError("unknown review state")
    if state["checks"] not in CHECK_STATES:
        raise TransitionError("unknown checks state")
    if state["policy"] not in POLICIES:
        raise TransitionError("unknown completion policy")
    if type(state["completion_note_saved"]) is not bool:
        raise TransitionError("completion_note_saved must be a boolean")
    return state


def next_action(state: dict) -> str:
    pr = state["pr"]
    review = state["review"]
    checks = state["checks"]
    policy = state["policy"]
    note_saved = state["completion_note_saved"]

    if pr == "closed":
        raise TransitionError("closed pull request cannot advance")
    if pr != "merged" and note_saved:
        raise TransitionError("an unmerged pull request cannot have a completion note")
    if pr == "absent":
        if review != "absent" or checks != "not_run":
            raise TransitionError("work without a pull request cannot have review or checks")
        return "implement"
    if pr == "merged":
        if review != "passed" or checks != "passed":
            raise TransitionError("merged pull request lacks passed review or checks")
        return "complete" if note_saved else "record_completion_note"
    if pr == "ready" and policy == "manual":
        raise TransitionError("manual policy cannot advance a ready pull request")
    if review == "absent":
        if checks != "not_run":
            raise TransitionError("checks cannot precede review")
        return "request_review"
    if review == "pending":
        if checks != "not_run":
            raise TransitionError("checks cannot run while review is pending")
        return "wait_review"
    if review == "changes_required":
        if checks != "not_run":
            raise TransitionError("checks cannot pass before review changes are resolved")
        return "address_review"
    if checks in {"not_run", "failed"}:
        return "verify"
    if checks == "pending":
        return "wait_checks"
    if pr == "draft":
        return "report_manual" if policy == "manual" else "mark_ready"
    return "merge"


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
