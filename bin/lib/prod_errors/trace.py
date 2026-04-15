from collections import Counter
import json
import re
import sys
from urllib.parse import urlparse

from prod_errors.ansi import (
    _BOLD,
    _CYAN,
    _DIM,
    _GREEN,
    _RED,
    _YELLOW,
    color,
    strip_ansi,
)
from prod_errors.client import (
    API_BASE,
    LoggingError,
    api_get,
    api_get_all_pages,
    build_group_stats_url,
    extract_trace_id,
    get_service_from_group,
    get_token,
    logging_read,
)
from prod_errors.timefmt import format_jst_timestamp


def cmd_trace(args):
    token = get_token()
    colors = _trace_colors()
    target = _lookup_error_group(args.project, token, args.group_id)
    result, first_line, known_service = _build_trace_result(args.group_id, target)

    if not args.json:
        _print_trace_header(args.group_id, colors)

    events = _load_recent_events(args.project, token, args.group_id)
    result["recentEvents"] = events

    filt = _build_cloud_logging_filter(first_line, known_service)
    result["cloudLogging"] = {"filter": filt}

    try:
        lookup = _lookup_cloud_logging(args.project, token, filt, args.freshness)
    except LoggingError as exc:
        result["cloudLogging"]["error"] = str(exc)
        _print_trace_error_result(
            args.json, result, f"**Cloud Logging query FAILED**: {exc}"
        )
        return

    if not lookup:
        result["cloudLogging"]["matched"] = False
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"No matching logs in Cloud Logging ({args.freshness} window).")
            if events:
                _print_recent_events(events, colors)
        return

    result["cloudLogging"].update(
        {
            "matched": True,
            "service": lookup["service"],
            "traceId": lookup["traceId"],
            "matchedEntries": lookup["matchedEntries"],
            "endpointCandidates": lookup["endpointCandidates"],
            "messageVariants": lookup["messageVariants"],
            "loggerClues": lookup["loggerClues"],
        }
    )
    if not args.json:
        if lookup["service"] and lookup["service"] != "unknown":
            print(f"- Service clue: {colors['dim'](lookup['service'])}")
        if lookup["traceId"]:
            print(f"- Cloud Trace ID: `{lookup['traceId']}`")
        else:
            print("- Cloud Trace ID: (not found)")
        _print_endpoint_summary(lookup["endpointCandidates"])
        _print_ranked_values("### Message Variants", lookup["messageVariants"], colors)
        _print_ranked_values("### Logger Clues", lookup["loggerClues"], colors)
        _print_log_entries(
            "### Matched Error Logs",
            list(reversed(lookup["matchedEntries"])),
            colors,
        )

    if not lookup["traceId"]:
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print("\nCloud Trace ID was not found in the matched log entry.")
            print(
                "Request-lifecycle lookup is unavailable, but the matched error logs above can be used to inspect this hotspot."
            )
        return

    try:
        trace_logs = _lookup_trace_lifecycle(
            args.project,
            token,
            lookup["service"],
            lookup["traceId"],
            args.freshness,
        )
    except LoggingError as exc:
        result["lifecycle"] = {"error": str(exc)}
        _print_trace_error_result(
            args.json, result, f"\n**Cloud Logging trace query FAILED**: {exc}"
        )
        return

    if trace_logs:
        lifecycle_entries = _build_lifecycle_entries(trace_logs)
        result["lifecycle"] = {
            "scope": "latest_event_only",
            "traceId": lookup["traceId"],
            "entries": lifecycle_entries,
        }
        if not args.json:
            _print_log_entries(
                "### Request Lifecycle (trace-level match)", lifecycle_entries, colors
            )
    else:
        result["lifecycle"] = {
            "scope": "latest_event_only",
            "traceId": lookup["traceId"],
            "entries": [],
        }

    endpoint, error_timestamp, http_status = _extract_retry_context(
        trace_logs, lookup["logs"]
    )
    if not endpoint or not error_timestamp:
        result["retryCheck"] = {"status": "could_not_extract_endpoint"}
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"\n{colors['bold']('### Retry Check')}\n")
            print("Could not extract endpoint. Manual investigation needed.")
        return

    if http_status is not None and http_status < 500:
        result["retryCheck"] = {
            "scope": "endpoint",
            "endpoint": endpoint,
            "httpStatus": http_status,
            "errorTimestamp": error_timestamp,
            "verdict": "error_within_success_response",
            "detail": (
                f"Endpoint returned HTTP {http_status} but ERROR was logged internally"
                ". Retry check not applicable."
            ),
        }
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"\n{colors['bold']('### Retry Check')}\n")
            print(f"- Endpoint: `{endpoint}` (HTTP {http_status})")
            print(
                f"- Error at: {format_jst_timestamp(error_timestamp, include_seconds=True, include_millis=True)}"
            )
            print(f"- Verdict: {colors['yellow']('Error within success response')}")
            print(
                f"  Endpoint returned HTTP {http_status} but ERROR was logged internally."
            )
            print(
                "  Retry check not applicable — the endpoint does not fail at HTTP level."
            )
        return

    if not args.json:
        print(f"\n{colors['bold']('### Retry Check')}\n")
        print(f"- Endpoint: `{endpoint}`")
        print(
            f"- Error at: {format_jst_timestamp(error_timestamp, include_seconds=True, include_millis=True)}"
        )

    try:
        _retry_filter, retry_logs = _lookup_retry_logs(
            args.project,
            token,
            lookup["service"],
            endpoint,
            error_timestamp,
            args.freshness,
        )
    except LoggingError as exc:
        result["retryCheck"] = {"error": str(exc)}
        _print_trace_error_result(
            args.json, result, f"**Retry check query FAILED**: {exc}"
        )
        return

    source_context = _collect_source_context(trace_logs, lookup["logs"])
    retry_summary = _summarize_retry_logs(retry_logs, source_context)
    result["retryCheck"] = {
        "scope": "endpoint",
        "endpoint": endpoint,
        "errorTimestamp": error_timestamp,
        "sourceContext": source_context,
        **retry_summary,
    }
    result["retryCheck"]["detail"] = _build_retry_detail(retry_summary, source_context)

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    print(
        "- Same-endpoint requests after this error "
        f"(within {args.freshness}): "
        f"{retry_summary['successCount']} ok / "
        f"{retry_summary['failureCount']} fail"
    )
    print(f"- Recovery match context: {_format_retry_context(source_context)}")
    if (
        retry_summary["sameTenantSuccessCount"]
        or retry_summary["sameTenantFailureCount"]
    ):
        print(
            "- Same tenant after error: "
            f"{retry_summary['sameTenantSuccessCount']} ok / "
            f"{retry_summary['sameTenantFailureCount']} fail"
        )
    if (
        retry_summary["sameCallerSuccessCount"]
        or retry_summary["sameCallerFailureCount"]
    ):
        print(
            "- Same caller after error: "
            f"{retry_summary['sameCallerSuccessCount']} ok / "
            f"{retry_summary['sameCallerFailureCount']} fail"
        )
    if retry_summary["firstSuccessTimestamp"]:
        print(
            f"- First success: {format_jst_timestamp(retry_summary['firstSuccessTimestamp'], include_seconds=True, include_millis=True)}"
        )
    print(f"- Verdict: {_format_retry_verdict(colors, retry_summary)}")
    print(f"  {result['retryCheck']['detail']}")


def _trace_colors():
    return {
        "bold": color(_BOLD),
        "cyan": color(_CYAN),
        "dim": color(_DIM),
        "green": color(_GREEN),
        "red": color(_RED),
        "yellow": color(_YELLOW),
        "severity": {
            "ERROR": color(_RED),
            "CRITICAL": color(_RED, _BOLD),
            "WARN": color(_YELLOW),
            "WARNING": color(_YELLOW),
            "INFO": color(_DIM),
            "DEBUG": color(_DIM),
        },
    }


def _summarize_log_entry(entry):
    payload = entry.get("jsonPayload", {})
    raw = payload.get("message", "") or entry.get("textPayload", "")
    return {
        "timestamp": entry.get("timestamp", ""),
        "severity": entry.get("severity", ""),
        "logger": payload.get("logger", ""),
        "message": strip_ansi(raw).split("\n")[0][:150],
    }


def _print_log_entries(title, entries, colors):
    if not entries:
        return
    print(f"\n{colors['bold'](title)}\n")
    for log_entry in entries:
        severity = log_entry["severity"]
        print(
            f"  [{format_jst_timestamp(log_entry['timestamp'], include_seconds=True, include_millis=True)}] "
            f"{colors['severity'].get(severity, color())(f'{severity:7s}')} "
            f"[{colors['dim'](log_entry['logger'])}] {log_entry['message']}"
        )


def _print_endpoint_summary(endpoint_candidates):
    if not endpoint_candidates:
        print("- Endpoint: (not found)")
        return

    primary = endpoint_candidates[0]
    statuses = _format_http_statuses(primary.get("httpStatuses", []))
    suffix = f" ({statuses})" if statuses else ""
    print(f"- Endpoint: `{primary['endpoint']}`{suffix}")

    if len(endpoint_candidates) > 1:
        print("\n### Endpoint Candidates\n")
        for candidate in endpoint_candidates:
            statuses = _format_http_statuses(candidate.get("httpStatuses", []))
            detail = f" | {statuses}" if statuses else ""
            print(f"  - `{candidate['endpoint']}` | {candidate['count']}{detail}")


def _print_ranked_values(title, items, colors):
    if not items:
        return

    print(f"\n{colors['bold'](title)}\n")
    for item in items:
        print(f"  - {item['value']} | {item['count']}")


def _lookup_error_group(project, token, group_id):
    groups = api_get_all_pages(build_group_stats_url(project), token, "errorGroupStats")
    target = next(
        (group for group in groups if group["group"].get("groupId") == group_id),
        None,
    )
    if not target:
        print(f"Error group {group_id} not found.", file=sys.stderr)
        sys.exit(1)
    return target


def _build_trace_result(group_id, target):
    representative_message = target.get("representative", {}).get("message", "")
    first_line = representative_message.split("\n")[0]
    known_service = get_service_from_group(target)
    result = {
        "groupId": group_id,
        "message": first_line,
        "count": int(target.get("count", "0")),
        "firstSeenTime": target.get("firstSeenTime", ""),
        "lastSeenTime": target.get("lastSeenTime", ""),
        "service": known_service or None,
    }
    return result, first_line, known_service


def _print_trace_header(group_id, colors):
    print(f"{colors['bold']('## Error Group:')} {colors['cyan'](group_id)}\n")


def _load_recent_events(project, token, group_id):
    event_data = api_get(
        f"{API_BASE}/projects/{project}/events"
        f"?groupId={group_id}&timeRange.period=PERIOD_30_DAYS&pageSize=5",
        token,
    )
    return [
        {
            "eventTime": event.get("eventTime", ""),
            "service": event.get("serviceContext", {}).get("service", "unknown"),
        }
        for event in event_data.get("errorEvents", [])
    ]


def _print_recent_events(events, colors):
    print(f"\n{colors['bold'](f'### Recent Events ({len(events)})')}\n")
    for event in events:
        print(
            f"  - {format_jst_timestamp(event['eventTime'], include_seconds=True)} | {colors['dim'](event['service'])}"
        )


def _build_cloud_logging_filter(first_line, known_service):
    search = first_line[:80].replace('"', '\\"')
    if known_service:
        return (
            f'resource.labels.service_name="{known_service}" "{search}" severity>=ERROR'
        )
    return f'"{search}" severity>=ERROR'


def _lookup_cloud_logging(project, token, filt, freshness):
    logs = logging_read(project, token, filt, limit=5, freshness=freshness)
    if not logs:
        return None

    entry = logs[0]
    resource_labels = entry.get("resource", {}).get("labels", {})
    service = resource_labels.get(
        "service_name", resource_labels.get("configuration_name", "unknown")
    )
    matched_logs = [_summarize_log_entry(log_entry) for log_entry in logs]
    trace_id = extract_trace_id(entry)
    endpoint_candidates = _collect_endpoint_candidates(logs)
    message_variants = _collect_message_variants(matched_logs)
    logger_clues = _collect_logger_clues(matched_logs)
    return {
        "logs": logs,
        "service": service,
        "matchedEntries": matched_logs,
        "traceId": trace_id or None,
        "endpointCandidates": endpoint_candidates,
        "messageVariants": message_variants,
        "loggerClues": logger_clues,
    }


def _lookup_trace_lifecycle(project, token, service, trace_id, freshness):
    trace_filter = (
        f'resource.labels.service_name="{service}" jsonPayload.trace_id="{trace_id}"'
    )
    trace_logs = logging_read(
        project, token, trace_filter, limit=50, freshness=freshness
    )
    if trace_logs:
        return trace_logs

    trace_filter = (
        f'resource.labels.service_name="{service}" '
        f'trace="projects/{project}/traces/{trace_id}"'
    )
    return logging_read(project, token, trace_filter, limit=50, freshness=freshness)


def _build_lifecycle_entries(trace_logs):
    return [
        {
            "timestamp": trace_log.get("timestamp", ""),
            "severity": trace_log.get("severity", ""),
            "logger": trace_log.get("jsonPayload", {}).get("logger", ""),
            "message": strip_ansi(
                trace_log.get("jsonPayload", {}).get("message", "")
                or trace_log.get("textPayload", "")
            ).split("\n")[0][:150],
        }
        for trace_log in reversed(trace_logs)
    ]


# Structured payload/header keys are normalized first and matched here.
# Add aliases here when the same caller context is available as explicit JSON keys.
_CONTEXT_KEY_ALIASES = {
    "tenantId": (
        "tenantid",
        "tenant_id",
        "apptenantid",
        "xtenantid",
        "xapptenantid",
    ),
    "userAccountId": (
        "appaccountid",
        "useraccountid",
        "user_account_id",
        "xappaccountid",
        "xuseraccountid",
    ),
    "userId": (
        "appuserid",
        "userid",
        "user_id",
        "xappuserid",
        "xuserid",
    ),
}

# Free-text payloads need a second path because some logs only expose caller context
# inside message strings rather than structured JSON fields.
_CONTEXT_VALUE_PATTERNS = {
    "tenantId": re.compile(
        r'(?i)(?:tenantId|tenant_id|appTenantId|app_tenant_id|x-tenant-id|x_tenant_id|x-app-tenant-id|x_app_tenant_id)["\'=:,\s]+([A-Za-z0-9._:-]+)'
    ),
    "userAccountId": re.compile(
        r'(?i)(?:appAccountId|app_account_id|userAccountId|user_account_id|x-app-account-id|x_app_account_id|x-user-account-id|x_user_account_id)["\'=:,\s]+([A-Za-z0-9._:-]+)'
    ),
    "userId": re.compile(
        r'(?i)(?:userId|user_id|appUserId|app_user_id|x-user-id|x_user_id|x-app-user-id|x_app_user_id)["\'=:,\s]+([A-Za-z0-9._:-]+)'
    ),
}

_ACCESS_LOG_RE = re.compile(
    r"(\d{3})\s+[\w ]+:\s+(GET|POST|PUT|PATCH|DELETE)\s+-\s+(.+?)\s+in\s+\d+ms"
)
_MAX_CONTEXT_DEPTH = 12

_ENDPOINT_CANDIDATE_FIELDS = (
    "path",
    "requestPath",
    "request_path",
    "endpoint",
    "uri",
    "url",
    "requestUrl",
    "request_url",
)
_STATUS_CANDIDATE_FIELDS = (
    "status",
    "statusCode",
    "status_code",
    "httpStatus",
    "http_status",
)


def _normalize_context_key(key):
    return re.sub(r"[^a-z0-9]", "", str(key).lower())


def _stringify_context_value(value):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (str, int, float)):
        text = str(value).strip()
        return text or None
    return None


def _merge_context_value(context, key, value):
    if key not in context and value:
        context[key] = value


def _extract_context_from_object(obj, context, depth=0):
    if depth > _MAX_CONTEXT_DEPTH:
        return
    if isinstance(obj, dict):
        for raw_key, value in obj.items():
            normalized_key = _normalize_context_key(raw_key)
            for context_key, aliases in _CONTEXT_KEY_ALIASES.items():
                if normalized_key in aliases:
                    _merge_context_value(
                        context, context_key, _stringify_context_value(value)
                    )
            _extract_context_from_object(value, context, depth + 1)
    elif isinstance(obj, list):
        for item in obj:
            _extract_context_from_object(item, context, depth + 1)
    elif isinstance(obj, str):
        for context_key, pattern in _CONTEXT_VALUE_PATTERNS.items():
            if context_key in context:
                continue
            match = pattern.search(obj)
            if match:
                _merge_context_value(context, context_key, match.group(1))


def _extract_log_context(log_entry):
    context = {}
    payload = log_entry.get("jsonPayload", {})
    _extract_context_from_object(payload, context)
    _extract_context_from_object(log_entry.get("httpRequest", {}), context)
    _extract_context_from_object(log_entry.get("labels", {}), context)
    raw = payload.get("message", "") or log_entry.get("textPayload", "")
    if raw:
        _extract_context_from_object(raw, context)
    return context


def _collect_source_context(*log_groups):
    context = {}
    for logs in log_groups:
        for log_entry in logs:
            extracted = _extract_log_context(log_entry)
            for key, value in extracted.items():
                _merge_context_value(context, key, value)
    return context


def _build_retry_contexts_by_trace_id(retry_logs):
    contexts_by_trace_id = {}
    for retry_log in retry_logs:
        trace_id = extract_trace_id(retry_log)
        if not trace_id:
            continue

        trace_context = contexts_by_trace_id.setdefault(trace_id, {})
        extracted = _extract_log_context(retry_log)
        for key, value in extracted.items():
            _merge_context_value(trace_context, key, value)
    return contexts_by_trace_id


def _format_http_statuses(statuses):
    if not statuses:
        return ""
    return ", ".join(f"HTTP {status}" for status in statuses)


def _collect_endpoint_candidates(logs, limit=5):
    counts = Counter()
    statuses_by_endpoint = {}
    order = []

    for log_entry in logs:
        request_info = _extract_http_request_info(log_entry)
        if not request_info or not request_info["endpoint"]:
            continue

        endpoint = request_info["endpoint"]
        if endpoint not in counts:
            order.append(endpoint)
        counts[endpoint] += 1

        http_status = request_info["httpStatus"]
        if http_status is not None:
            statuses = statuses_by_endpoint.setdefault(endpoint, [])
            if http_status not in statuses:
                statuses.append(http_status)

    ranked = sorted(
        order, key=lambda endpoint: (-counts[endpoint], order.index(endpoint))
    )
    return [
        {
            "endpoint": endpoint,
            "count": counts[endpoint],
            "httpStatuses": statuses_by_endpoint.get(endpoint, []),
        }
        for endpoint in ranked[:limit]
    ]


def _collect_message_variants(matched_logs, limit=5):
    counts = Counter()
    order = []

    for log_entry in matched_logs:
        message = log_entry.get("message", "").strip()
        if not message:
            continue
        if message not in counts:
            order.append(message)
        counts[message] += 1

    ranked = sorted(order, key=lambda message: (-counts[message], order.index(message)))
    return [{"value": message, "count": counts[message]} for message in ranked[:limit]]


def _collect_logger_clues(matched_logs, limit=5):
    counts = Counter()
    order = []

    for log_entry in matched_logs:
        logger = log_entry.get("logger", "").strip()
        if not logger:
            continue
        if logger not in counts:
            order.append(logger)
        counts[logger] += 1

    ranked = sorted(order, key=lambda logger: (-counts[logger], order.index(logger)))
    return [{"value": logger, "count": counts[logger]} for logger in ranked[:limit]]


def _coerce_http_status(value):
    if value is None or value == "" or isinstance(value, bool):
        return None
    try:
        code = int(value)
    except (TypeError, ValueError):
        return None
    return code if 100 <= code < 600 else None


def _normalize_endpoint_value(value):
    if value in (None, ""):
        return None

    text = str(value).strip()
    if not text:
        return None

    parsed = urlparse(text)
    if parsed.scheme and parsed.netloc:
        path = parsed.path or "/"
        if parsed.query:
            return f"{path}?{parsed.query}"
        return path

    return text


def _extract_http_request_info(log_entry):
    payload = log_entry.get("jsonPayload", {})
    raw = payload.get("message", "") or log_entry.get("textPayload", "")
    message = strip_ansi(raw)
    match = _ACCESS_LOG_RE.search(message)
    if match:
        return {
            "httpStatus": int(match.group(1)),
            "endpoint": match.group(3).strip(),
        }

    candidates = [log_entry.get("httpRequest", {}), payload.get("httpRequest", {})]
    if isinstance(payload.get("request"), dict):
        candidates.append(payload["request"])
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        endpoint = next(
            (
                value
                for field in _ENDPOINT_CANDIDATE_FIELDS
                if (value := _normalize_endpoint_value(candidate.get(field)))
            ),
            None,
        )
        http_status = next(
            (
                value
                for field in _STATUS_CANDIDATE_FIELDS
                if (value := _coerce_http_status(candidate.get(field))) is not None
            ),
            None,
        )
        if endpoint:
            return {
                "httpStatus": http_status,
                "endpoint": endpoint,
            }

    return None


def _match_same_tenant(source_context, retry_context):
    source_tenant = source_context.get("tenantId")
    retry_tenant = retry_context.get("tenantId")
    return bool(source_tenant and retry_tenant and source_tenant == retry_tenant)


def _match_same_caller(source_context, retry_context):
    if not _match_same_tenant(source_context, retry_context):
        return False
    for key in ("userAccountId", "userId"):
        source_value = source_context.get(key)
        retry_value = retry_context.get(key)
        if source_value and retry_value and source_value == retry_value:
            return True
    return False


def _extract_retry_log_entry(log_entry, contexts_by_trace_id=None):
    request_info = _extract_http_request_info(log_entry)
    if not request_info or request_info["endpoint"] is None:
        return None

    context = _extract_log_context(log_entry)
    if contexts_by_trace_id:
        trace_id = extract_trace_id(log_entry)
        if trace_id:
            for key, value in contexts_by_trace_id.get(trace_id, {}).items():
                _merge_context_value(context, key, value)

    return {
        "timestamp": log_entry.get("timestamp", ""),
        "httpStatus": request_info["httpStatus"],
        "endpoint": request_info["endpoint"],
        "context": context,
    }


def _extract_retry_context(trace_logs, logs):
    endpoint = None
    error_timestamp = None
    http_status = None
    error_timestamps = []
    trace_access_logs = []
    matched_access_logs = []

    for trace_log in trace_logs:
        if trace_log.get("severity", "") in ("ERROR", "CRITICAL"):
            error_timestamps.append(trace_log.get("timestamp", ""))
        access_log = _extract_retry_log_entry(trace_log)
        if access_log:
            trace_access_logs.append(access_log)

    for log_entry in logs:
        access_log = _extract_retry_log_entry(log_entry)
        if access_log:
            matched_access_logs.append(access_log)

    if error_timestamps:
        error_timestamp = error_timestamps[0]
    elif logs:
        error_timestamp = logs[0].get("timestamp", "")

    access_logs = trace_access_logs or matched_access_logs
    if access_logs:
        errors_5xx = [
            log
            for log in access_logs
            if log["httpStatus"] is not None and log["httpStatus"] >= 500
        ]
        chosen = errors_5xx[0] if errors_5xx else access_logs[0]
        endpoint = chosen["endpoint"]
        http_status = chosen["httpStatus"]

    return endpoint, error_timestamp, http_status


def _lookup_retry_logs(project, token, service, endpoint, error_timestamp, freshness):
    escaped_endpoint = endpoint.replace('"', '\\"')
    retry_filter = (
        f'resource.labels.service_name="{service}" '
        f'jsonPayload.message:"{escaped_endpoint}" '
        f'timestamp>="{error_timestamp}"'
    )
    retry_logs = logging_read(
        project, token, retry_filter, limit=30, freshness=freshness
    )
    return retry_filter, retry_logs


def _summarize_retry_logs(retry_logs, source_context):
    ok = 0
    fail = 0
    first_ok_timestamp = None
    same_tenant_ok = 0
    same_tenant_fail = 0
    first_same_tenant_ok_timestamp = None
    same_caller_ok = 0
    same_caller_fail = 0
    first_same_caller_ok_timestamp = None
    contexts_by_trace_id = _build_retry_contexts_by_trace_id(retry_logs)

    for retry_log in reversed(retry_logs):
        retry_entry = _extract_retry_log_entry(retry_log, contexts_by_trace_id)
        if not retry_entry:
            continue

        status = retry_entry["httpStatus"]
        retry_context = retry_entry["context"]
        timestamp = retry_log.get("timestamp", "")

        if status is None:
            continue
        if 200 <= status < 300:
            ok += 1
            if first_ok_timestamp is None:
                first_ok_timestamp = timestamp
            if _match_same_tenant(source_context, retry_context):
                same_tenant_ok += 1
                if first_same_tenant_ok_timestamp is None:
                    first_same_tenant_ok_timestamp = timestamp
            if _match_same_caller(source_context, retry_context):
                same_caller_ok += 1
                if first_same_caller_ok_timestamp is None:
                    first_same_caller_ok_timestamp = timestamp
        elif status >= 500:
            fail += 1
            if _match_same_tenant(source_context, retry_context):
                same_tenant_fail += 1
            if _match_same_caller(source_context, retry_context):
                same_caller_fail += 1

    if same_caller_ok > 0:
        verdict = "recovered_same_caller"
        first_success_timestamp = first_same_caller_ok_timestamp
    elif same_tenant_ok > 0:
        verdict = "recovered_same_tenant"
        first_success_timestamp = first_same_tenant_ok_timestamp
    elif ok > 0:
        verdict = "recovered_endpoint_only"
        first_success_timestamp = first_ok_timestamp
    elif fail > 0:
        verdict = "not_recovered"
        first_success_timestamp = None
    else:
        verdict = "no_subsequent_requests"
        first_success_timestamp = None

    return {
        "successCount": ok,
        "failureCount": fail,
        "firstSuccessTimestamp": first_success_timestamp,
        "sameTenantSuccessCount": same_tenant_ok,
        "sameTenantFailureCount": same_tenant_fail,
        "firstSameTenantSuccessTimestamp": first_same_tenant_ok_timestamp,
        "sameCallerSuccessCount": same_caller_ok,
        "sameCallerFailureCount": same_caller_fail,
        "firstSameCallerSuccessTimestamp": first_same_caller_ok_timestamp,
        "verdict": verdict,
    }


def _build_retry_detail(retry_summary, source_context):
    verdict = retry_summary["verdict"]
    if verdict == "recovered_same_caller":
        return (
            "Subsequent success found on the same endpoint with matching tenant and "
            "caller context."
        )
    if verdict == "recovered_same_tenant":
        return "Subsequent success found on the same endpoint for the same tenant."
    if verdict == "recovered_endpoint_only":
        missing_context = []
        if not source_context.get("tenantId"):
            missing_context.append("tenantId")
        if not source_context.get("userAccountId") and not source_context.get("userId"):
            missing_context.append("caller")
        if missing_context:
            joined = ", ".join(missing_context)
            return (
                "Subsequent success found on the same endpoint, but stronger matching "
                f"context was unavailable ({joined})."
            )
        return (
            "Subsequent success found on the same endpoint, but tenant/caller match "
            "was not confirmed."
        )
    if verdict == "not_recovered":
        return "No subsequent success found on the same endpoint after the error."
    return "No subsequent requests were found on the same endpoint after the error."


def _format_retry_context(context):
    parts = []
    if context.get("tenantId"):
        parts.append(f"tenantId={context['tenantId']}")
    if context.get("userAccountId"):
        parts.append(f"userAccountId={context['userAccountId']}")
    if context.get("userId"):
        parts.append(f"userId={context['userId']}")
    return ", ".join(parts) if parts else "(unavailable)"


def _format_retry_verdict(colors, retry_summary):
    verdict = retry_summary["verdict"]
    if verdict == "recovered_same_caller":
        return colors["green"]("Recovered (same caller)")
    if verdict == "recovered_same_tenant":
        return colors["green"]("Recovered (same tenant)")
    if verdict == "recovered_endpoint_only":
        return colors["yellow"]("Recovered (endpoint only)")
    if verdict == "not_recovered":
        return colors["red"]("Not recovered")
    return colors["yellow"]("Unknown")


def _print_trace_error_result(as_json, result, message):
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(message)
    if message.startswith("**Cloud Logging query FAILED**"):
        print("Cannot determine if logs exist. Check auth and filter syntax.")
