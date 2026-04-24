from collections import Counter
from datetime import timedelta
import re

from prod_errors.client import LoggingError, extract_trace_id, logging_read
from prod_errors.fingerprint import build_request_row
from prod_errors.timefmt import isoformat_utc, parse_timestamp

_WINDOW_RE = re.compile(r"^(\d+)([smh])$")
_CONSTRAINT_TERMS = (
    "duplicate key value violates unique constraint",
    "violates unique constraint",
    "duplicate key",
)


def parse_window(value):
    match = _WINDOW_RE.match(value or "")
    if not match:
        raise ValueError("expected window format like 5m, 30s, or 1h")
    amount = int(match.group(1))
    unit = match.group(2)
    if amount <= 0:
        raise ValueError("window must be greater than 0")
    if unit == "s":
        return timedelta(seconds=amount)
    if unit == "m":
        return timedelta(minutes=amount)
    return timedelta(hours=amount)


def build_request_correlation(
    project,
    token,
    service,
    endpoint,
    error_timestamp,
    window,
    extract_http_request_info,
):
    window_delta = parse_window(window)
    error_dt = parse_timestamp(error_timestamp)
    if not error_dt:
        raise ValueError("error timestamp is unavailable")

    since = isoformat_utc(error_dt - window_delta)
    until = isoformat_utc(error_dt + window_delta)
    request_filter = _build_request_filter(service, endpoint, since, until)
    request_logs = logging_read(
        project, token, request_filter, limit=100, freshness=None
    )
    requests = _build_request_rows(request_logs, endpoint, extract_http_request_info)
    constraint_errors = _lookup_constraint_errors(project, token, service, since, until)
    replay_check = _build_replay_check(requests)
    summary = _build_summary(requests, replay_check, window)

    return {
        "summary": summary,
        "window": {"since": since, "until": until, "duration": window},
        "filter": request_filter,
        "correlatedRequests": requests,
        "replayCheck": replay_check,
        "relatedConstraintErrors": constraint_errors,
        "nextHints": _build_next_hints(requests, replay_check, constraint_errors),
    }


def _build_request_filter(service, endpoint, since, until):
    escaped_endpoint = endpoint.replace('"', '\\"')
    service_filter = (
        f'resource.labels.service_name="{service}" '
        if service and service != "unknown"
        else ""
    )
    return (
        f'{service_filter}"{escaped_endpoint}" timestamp>="{since}" timestamp<"{until}"'
    )


def _build_request_rows(logs, target_endpoint, extract_http_request_info):
    grouped = {}
    order = []
    for log_entry in reversed(logs):
        request_info = extract_http_request_info(log_entry)
        if not request_info or request_info["endpoint"] != target_endpoint:
            continue
        row = build_request_row(
            log_entry,
            request_info["endpoint"],
            request_info["httpStatus"],
        )
        key = _request_group_key(row, log_entry)
        if key not in grouped:
            grouped[key] = row
            order.append(key)
            continue
        _merge_request_row(grouped[key], row)
    return [grouped[key] for key in order]


def _request_group_key(row, log_entry):
    if row["traceId"]:
        return f"trace:{row['traceId']}"
    if row["requestId"]:
        return f"request:{row['requestId']}"
    trace = extract_trace_id(log_entry)
    if trace:
        return f"trace:{trace}"
    return f"entry:{row['timestamp']}"


def _merge_request_row(base, incoming):
    if base["status"] is None and incoming["status"] is not None:
        base["status"] = incoming["status"]
    if not base["traceId"] and incoming["traceId"]:
        base["traceId"] = incoming["traceId"]
    if not base["requestId"] and incoming["requestId"]:
        base["requestId"] = incoming["requestId"]
    if _fingerprint_score(incoming["fingerprint"]) > _fingerprint_score(
        base["fingerprint"]
    ):
        base["fingerprint"] = incoming["fingerprint"]


def _fingerprint_score(fingerprint):
    return int(bool(fingerprint["requestId"])) + len(fingerprint["fileIds"])


def _lookup_constraint_errors(project, token, service, since, until):
    terms_filter = " OR ".join(f'"{term}"' for term in _CONSTRAINT_TERMS)
    service_filter = (
        f'resource.labels.service_name="{service}" '
        if service and service != "unknown"
        else ""
    )
    filt = f'{service_filter}({terms_filter}) timestamp>="{since}" timestamp<"{until}"'
    try:
        logs = logging_read(project, token, filt, limit=20, freshness=None)
    except LoggingError:
        return []
    return [
        {
            "timestamp": log_entry.get("timestamp", ""),
            "severity": log_entry.get("severity", ""),
            "message": _first_message_line(log_entry),
        }
        for log_entry in reversed(logs)
    ]


def _first_message_line(log_entry):
    payload = log_entry.get("jsonPayload", {})
    raw = payload.get("message", "") or log_entry.get("textPayload", "")
    return str(raw).split("\n")[0][:200]


def _build_replay_check(requests):
    request_ids = [row["requestId"] for row in requests if row["requestId"]]
    file_sets = [
        tuple(row["fingerprint"]["fileIds"])
        for row in requests
        if row["fingerprint"]["fileIds"]
    ]
    statuses = [row["status"] for row in requests if row["status"] is not None]
    signals = []
    fingerprint_available = bool(request_ids or file_sets)
    if _has_duplicate(request_ids):
        signals.append("same_request_id")
    if _has_duplicate(file_sets):
        signals.append("same_file_ids")
    if len(requests) > 1:
        signals.append("same_endpoint")
    if _has_success_then_failure(statuses):
        signals.append("success_then_failure")

    if requests and not fingerprint_available:
        verdict = "fingerprint_unavailable"
    elif {"same_request_id", "same_file_ids", "success_then_failure"}.issubset(signals):
        verdict = "likely_resubmit"
    elif {"same_request_id", "same_file_ids"}.issubset(signals):
        verdict = "same_payload_seen"
    elif "same_endpoint" in signals and _has_failure(statuses):
        verdict = "endpoint_failures_seen"
    else:
        verdict = "no_replay_signal"

    return {
        "signals": signals,
        "verdict": verdict,
        "fingerprintAvailable": fingerprint_available,
        "sameRequestIdCount": _duplicate_value_count(request_ids),
        "sameFileIdsCount": _duplicate_value_count(file_sets),
    }


def _build_summary(requests, replay_check, window):
    success_count = sum(1 for row in requests if _is_success(row["status"]))
    failure_count = sum(1 for row in requests if _is_failure(row["status"]))
    return {
        "text": _summary_text(
            len(requests), success_count, failure_count, replay_check, window
        ),
        "requestCount": len(requests),
        "successCount": success_count,
        "failureCount": failure_count,
        "replayVerdict": replay_check["verdict"],
    }


def _build_next_hints(requests, replay_check, constraint_errors):
    hints = []
    if replay_check["verdict"] == "fingerprint_unavailable":
        hints.append("inspect raw Request Information logs for requestBody shape")
    if replay_check["verdict"] in {"likely_resubmit", "same_payload_seen"}:
        hints.append("compare caller and UI retry/resubmit path")
    if constraint_errors:
        hints.append("inspect related constraint error root cause")
    if not requests:
        hints.append("broaden --window or verify endpoint extraction")
    return hints


def _summary_text(request_count, success_count, failure_count, replay_check, window):
    if request_count and replay_check["verdict"] == "fingerprint_unavailable":
        return (
            f"{request_count} same-endpoint requests within {window}; "
            f"{success_count} success / {failure_count} failure; "
            "comparison unavailable: request fingerprint extraction failed"
        )
    return (
        f"{request_count} same-endpoint requests within {window}; "
        f"{success_count} success / {failure_count} failure; "
        f"replay={replay_check['verdict']}"
    )


def _has_duplicate(values):
    return any(count > 1 for count in Counter(values).values())


def _duplicate_value_count(values):
    return sum(1 for count in Counter(values).values() if count > 1)


def _has_success_then_failure(statuses):
    seen_success = False
    for status in statuses:
        if _is_success(status):
            seen_success = True
        elif seen_success and _is_failure(status):
            return True
    return False


def _has_failure(statuses):
    return any(_is_failure(status) for status in statuses)


def _is_success(status):
    return status is not None and 200 <= status < 300


def _is_failure(status):
    return status is not None and status >= 500
