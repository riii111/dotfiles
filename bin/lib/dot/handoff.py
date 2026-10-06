import json
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import urlsplit


COMPLETION_TARGETS = {
    "implementation": "実装・検証まで",
    "draft_pr": "Draft PR・CI成功まで",
    "merge": "マージまで",
}


class HandoffError(Exception):
    pass


def read_request(path, required, optional=()):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise HandoffError("request must be a JSON object")
    unknown = data.keys() - set(required) - set(optional)
    if unknown:
        raise HandoffError("unknown request fields: " + ", ".join(sorted(unknown)))
    missing = set(required) - data.keys()
    if missing:
        raise HandoffError("missing request fields: " + ", ".join(sorted(missing)))
    return data


def single_line(value, name):
    if (
        not isinstance(value, str)
        or not value.strip()
        or any(ord(char) < 32 for char in value)
    ):
        raise HandoffError(f"{name} must be a nonempty single-line string")
    return value


def task_id(value):
    single_line(value, "taskId")
    if not re.fullmatch(r"[\w#][\w.#/-]*", value):
        raise HandoffError("taskId must be an identifier without prose or spaces")
    return value


def chat_id(value, name):
    single_line(value, name)
    if any(char.isspace() for char in value) or value.startswith("client-new-thread:"):
        raise HandoffError(f"{name} must be a confirmed chat ID without whitespace")
    return value


def document_refs(values):
    if not isinstance(values, list) or not values:
        raise HandoffError("documentRefs must be a nonempty list of paths or URLs")
    for value in values:
        single_line(value, "documentRefs entry")
        url = urlsplit(value)
        if url.scheme == "https" and url.netloc and not any(c.isspace() for c in value):
            continue
        path = Path(value)
        if not path.is_absolute() or not path.exists():
            raise HandoffError(
                f"document reference must be an existing absolute path or HTTPS URL: {value}"
            )
    if len(set(values)) != len(values):
        raise HandoffError("documentRefs must not contain duplicate references")
    return "\n".join("- " + value for value in values)


def skills_root():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "skills"


def launch_request(path):
    data = read_request(
        path, ("taskId", "documentRefs", "completionTarget", "projectId")
    )
    task_id(data["taskId"])
    single_line(data["projectId"], "projectId")
    document_refs(data["documentRefs"])
    if data["completionTarget"] not in COMPLETION_TARGETS:
        raise HandoffError(
            "completionTarget must be implementation, draft_pr, or merge"
        )
    return data


def worker_prompt(data, skills):
    skill = skills / "task-worker/SKILL.md"
    template = skills / "task-session-launch/references/worker.md"
    if not skill.is_file() or not template.is_file():
        raise HandoffError("task-worker or worker template is not installed")
    return template.read_text().format(
        task_id=data["taskId"],
        document_refs=document_refs(data["documentRefs"]),
        completion_target=COMPLETION_TARGETS[data["completionTarget"]],
        worker_skill_path=str(skill.resolve()),
    )


def git(checkout, *args):
    result = subprocess.run(
        ["git", "-C", str(checkout), *args], capture_output=True, text=True
    )
    if result.returncode:
        raise HandoffError(result.stderr.strip())
    return result.stdout.strip()


def review_request(path):
    data = read_request(
        path,
        ("taskId", "workerAI", "projectId", "checkout", "baseBranch", "documentRefs"),
        ("prUrl",),
    )
    task_id(data["taskId"])
    document_refs(data["documentRefs"])
    for key in ("projectId", "checkout", "baseBranch"):
        single_line(data[key], key)
    if data["workerAI"] not in ("Claude", "Codex"):
        raise HandoffError("workerAI must be Claude or Codex")
    if data.get("prUrl") is not None and (
        not isinstance(data["prUrl"], str)
        or not re.fullmatch(
            r"https://[^/\s]+/[^/\s]+/[^/\s]+/pull/[1-9][0-9]*/?", data["prUrl"]
        )
    ):
        raise HandoffError("prUrl must be a pull request URL or null")
    data.setdefault("prUrl", None)
    checkout = Path(data["checkout"])
    if not checkout.is_absolute() or not checkout.is_dir():
        raise HandoffError("checkout must be an existing absolute directory")
    data["checkout"] = str(checkout.resolve())
    return data


def candidate(data, previous, update_base):
    checkout = data["checkout"]
    if git(checkout, "status", "--porcelain", "--untracked-files=no"):
        raise HandoffError("checkout has uncommitted tracked changes")
    data["head"] = git(checkout, "rev-parse", "HEAD")
    if previous and not update_base:
        if previous.get("baseBranch") not in (None, data["baseBranch"]):
            raise HandoffError(
                "baseBranch changed; use --update-base after integrating upstream"
            )
        data["base"] = previous["base"]
    else:
        reference = git(
            checkout,
            "rev-parse",
            "--symbolic-full-name",
            "--verify",
            "--end-of-options",
            data["baseBranch"],
        )
        if not reference.startswith(("refs/heads/", "refs/remotes/")):
            raise HandoffError("baseBranch must name a local or remote branch")
        data["base"] = git(checkout, "rev-parse", "--verify", reference + "^{commit}")
    if git(checkout, "merge-base", data["base"], data["head"]) != data["base"]:
        raise HandoffError("review base must be an ancestor of head")
    return data


def session_value(data, key):
    old_names = {
        "taskId": "identifier",
        "workerAI": "worker",
        "workerChatId": "workerId",
    }
    value = data.get(key, data.get(old_names.get(key)))
    return str(Path(value).resolve()) if key == "checkout" and value else value


def review_prompt(data, skills):
    references = skills / "task-review-cycle/references"
    paths = {
        "skill_path": skills / "ai-code-review/SKILL.md",
        "cycle_skill_path": skills / "task-review-cycle/SKILL.md",
        "reply_path": references / ("reply-" + data["workerAI"].lower() + ".md"),
    }
    template = references / "reviewer.md"
    if not all(path.is_file() for path in (template, *paths.values())):
        raise HandoffError("ai-code-review or reviewer templates are not installed")
    return template.read_text().format(
        **{key: str(path.resolve()) for key, path in paths.items()},
        task_id=data["taskId"],
        document_refs=document_refs(data["documentRefs"]),
        worker_ai=data["workerAI"],
        worker_chat_id=data["workerChatId"],
        checkout=data["checkout"],
        pr_url=data["prUrl"] or "null",
        base=data["base"],
        head=data["head"],
    )
