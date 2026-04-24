import json
import re

from prod_errors.client import extract_trace_id

_UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
_REQUEST_ID_KEYS = {"requestid", "request_id"}
_REQUEST_ID_RE = re.compile(
    r"(?i)(?:requestBody\.)?(?:requestId|request_id|id)[\"'=:\s]+([0-9a-f-]{36})"
)
_FILE_ID_RE = re.compile(
    r"(?i)(?:files?\[\]?\.)?(?:fileId|file_id|fileUuid|file_uuid|id)[\"'=:\s]+([0-9a-f-]{36})"
)
_CALLER_KEYS = {
    "tenantId": {"tenantid", "tenant_id", "apptenantid", "xtenantid", "xapptenantid"},
    "userAccountId": {
        "useraccountid",
        "user_account_id",
        "appaccountid",
        "xuseraccountid",
        "xappaccountid",
    },
    "userId": {"userid", "user_id", "appuserid", "xuserid", "xappuserid"},
}


def extract_request_fingerprint(entry):
    payload = entry.get("jsonPayload", {})
    request_body = _extract_request_body(payload)
    source = request_body if isinstance(request_body, (dict, list)) else payload
    request_id = _extract_request_id(source)
    file_ids = [value for value in _extract_file_ids(source) if value != request_id]
    primary_ids = _extract_primary_ids(source, file_ids, request_id)
    caller = _extract_caller(entry)

    return {
        "requestId": request_id,
        "fileIds": file_ids,
        "primaryIds": primary_ids,
        "caller": caller,
        "summary": _format_fingerprint_summary(request_id, file_ids, primary_ids),
    }


def _extract_request_body(payload):
    for key in ("requestBody", "request_body", "body"):
        value = payload.get(key)
        if isinstance(value, str):
            return _parse_json_object(value)
        if isinstance(value, (dict, list)):
            return value
    message = payload.get("message", "")
    if isinstance(message, str):
        match = re.search(r"requestBody[=:]\s*(\{.*\})", message)
        if match:
            return _parse_json_object(match.group(1))
    return None


def _parse_json_object(value):
    try:
        parsed = json.loads(value)
    except (TypeError, ValueError):
        return None
    return parsed if isinstance(parsed, (dict, list)) else None


def _normalize_key(key):
    return re.sub(r"[^a-z0-9]", "", str(key).lower())


def _extract_request_id(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            normalized = _normalize_key(key)
            if normalized in _REQUEST_ID_KEYS or normalized == "id":
                text = _string_value(value)
                if text:
                    return text
        for value in obj.values():
            found = _extract_request_id(value)
            if found:
                return found
    if isinstance(obj, list):
        for value in obj:
            found = _extract_request_id(value)
            if found:
                return found
    if isinstance(obj, str):
        match = _REQUEST_ID_RE.search(obj)
        if match:
            return match.group(1)
    return None


def _extract_file_ids(obj):
    ids = []
    _collect_file_ids(obj, ids)
    return _unique(ids)


def _collect_file_ids(obj, ids, inside_files=False):
    if isinstance(obj, dict):
        for key, value in obj.items():
            normalized = _normalize_key(key)
            in_file_scope = inside_files or normalized in {
                "files",
                "fileids",
                "fileuuids",
            }
            if normalized in {"fileid", "fileuuid"}:
                text = _string_value(value)
                if text:
                    ids.append(text)
            elif in_file_scope and normalized == "id":
                text = _string_value(value)
                if text:
                    ids.append(text)
            _collect_file_ids(value, ids, in_file_scope)
    elif isinstance(obj, list):
        for value in obj:
            _collect_file_ids(value, ids, inside_files)
    elif isinstance(obj, str):
        ids.extend(match.group(1) for match in _FILE_ID_RE.finditer(obj))


def _extract_primary_ids(obj, file_ids, request_id):
    ids = []
    _collect_uuids(obj, ids)
    excluded = set(file_ids)
    if request_id:
        excluded.add(request_id)
    return [value for value in _unique(ids) if value not in excluded][:5]


def _collect_uuids(obj, ids):
    if isinstance(obj, dict):
        for value in obj.values():
            _collect_uuids(value, ids)
    elif isinstance(obj, list):
        for value in obj:
            _collect_uuids(value, ids)
    elif isinstance(obj, str):
        ids.extend(match.group(0) for match in _UUID_RE.finditer(obj))


def _extract_caller(entry):
    caller = {}
    for source in (
        entry.get("jsonPayload", {}),
        entry.get("httpRequest", {}),
        entry.get("labels", {}),
    ):
        _collect_caller(source, caller)
    return caller


def _collect_caller(obj, caller):
    if isinstance(obj, dict):
        for key, value in obj.items():
            normalized = _normalize_key(key)
            for caller_key, aliases in _CALLER_KEYS.items():
                if caller_key not in caller and normalized in aliases:
                    text = _string_value(value)
                    if text:
                        caller[caller_key] = text
            _collect_caller(value, caller)
    elif isinstance(obj, list):
        for value in obj:
            _collect_caller(value, caller)


def _string_value(value):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (str, int, float)):
        text = str(value).strip()
        return text or None
    return None


def _unique(values):
    seen = set()
    result = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def build_request_row(entry, endpoint, http_status):
    fingerprint = extract_request_fingerprint(entry)
    return {
        "timestamp": entry.get("timestamp", ""),
        "status": http_status,
        "traceId": extract_trace_id(entry) or None,
        "endpoint": endpoint,
        "requestId": fingerprint["requestId"],
        "fingerprint": fingerprint,
    }


def _format_fingerprint_summary(request_id, file_ids, primary_ids):
    parts = []
    if request_id:
        parts.append(f"request_id={_shorten(request_id)}")
    if file_ids:
        parts.append(
            f"files={len(file_ids)}:{','.join(_shorten(v) for v in file_ids[:3])}"
        )
    if primary_ids:
        parts.append(f"ids={','.join(_shorten(v) for v in primary_ids[:3])}")
    return " ".join(parts) if parts else "(no fingerprint)"


def _shorten(value):
    if len(value) <= 12:
        return value
    return f"{value[:8]}..."
