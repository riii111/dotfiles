import json
import re
from pathlib import Path
from urllib.parse import urlsplit


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
    import os

    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "skills"
