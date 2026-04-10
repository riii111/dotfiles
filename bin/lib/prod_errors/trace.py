import json
import re
import sys

from prod_errors.ansi import _BOLD, _CYAN, _DIM, _GREEN, _RED, _YELLOW, color, strip_ansi
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
            f"  [{log_entry['timestamp'][:23]}] "
            f"{colors['severity'].get(severity, color())(f'{severity:7s}')} "
            f"[{colors['dim'](log_entry['logger'])}] {log_entry['message']}"
        )


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


def _print_trace_header(group_id, target, known_service, colors):
    print(f"{colors['bold']('## Error Group:')} {colors['cyan'](group_id)}\n")
    print(f"- Message: {target.get('representative', {}).get('message', '').splitlines()[0][:120]}")
    print(f"- Count: {target.get('count', '0')}")
    print(f"- First: {target.get('firstSeenTime', '')[:19]}Z")
    print(f"- Last:  {target.get('lastSeenTime', '')[:19]}Z")
    if known_service:
        print(f"- Service (from Error Reporting): {colors['dim'](known_service)}")


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
        print(f"  - {event['eventTime'][:19]}Z | {colors['dim'](event['service'])}")


def _build_cloud_logging_filter(first_line, known_service):
    search = first_line[:80].replace('"', '\\"')
    if known_service:
        return (
            f'resource.labels.service_name="{known_service}" '
            f'"{search}" severity>=ERROR'
        )
    return f'"{search}" severity>=ERROR'


def _lookup_cloud_logging(project, token, filt, freshness):
    logs = logging_read(project, token, filt, limit=3, freshness=freshness)
    if not logs:
        return None

    entry = logs[0]
    resource_labels = entry.get("resource", {}).get("labels", {})
    service = resource_labels.get(
        "service_name", resource_labels.get("configuration_name", "unknown")
    )
    matched_logs = [_summarize_log_entry(log_entry) for log_entry in logs]
    trace_id = extract_trace_id(entry)
    return {
        "logs": logs,
        "service": service,
        "matchedEntries": matched_logs,
        "traceId": trace_id or None,
    }


def _print_cloud_logging_lookup(filt, lookup, colors):
    print(f"\n{colors['bold']('### Cloud Logging Lookup')}\n")
    print(f"Filter: `{filt}`\n")
    print(f"- Service: {colors['bold'](lookup['service'])}")
    if lookup["traceId"]:
        print(f"- Cloud Trace ID: `{lookup['traceId']}`")
    else:
        print("- Cloud Trace ID: (not found)")
    _print_log_entries(
        "### Matched Error Logs",
        list(reversed(lookup["matchedEntries"])),
        colors,
    )


def _lookup_trace_lifecycle(project, token, service, trace_id, freshness):
    trace_filter = (
        f'resource.labels.service_name="{service}" jsonPayload.trace_id="{trace_id}"'
    )
    trace_logs = logging_read(project, token, trace_filter, limit=50, freshness=freshness)
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


def _extract_retry_context(trace_logs, logs):
    access_log_re = re.compile(
        r"(\d{3})\s+[\w ]+:\s+(GET|POST|PUT|PATCH|DELETE)\s+-\s+(.+?)\s+in\s+\d+ms"
    )
    endpoint = None
    error_timestamp = None
    http_status = None
    error_timestamps = []
    access_logs = []

    for trace_log in trace_logs:
        payload = trace_log.get("jsonPayload", {})
        raw = payload.get("message", "") or trace_log.get("textPayload", "")
        clean = strip_ansi(raw)
        if trace_log.get("severity", "") in ("ERROR", "CRITICAL"):
            error_timestamps.append(trace_log.get("timestamp", ""))
        match = access_log_re.search(clean)
        if match:
            access_logs.append(
                {
                    "timestamp": trace_log.get("timestamp", ""),
                    "httpStatus": int(match.group(1)),
                    "endpoint": match.group(3).strip(),
                }
            )

    if error_timestamps:
        error_timestamp = error_timestamps[0]
    elif logs:
        error_timestamp = logs[0].get("timestamp", "")

    if access_logs:
        errors_5xx = [log for log in access_logs if log["httpStatus"] >= 500]
        chosen = errors_5xx[0] if errors_5xx else access_logs[0]
        endpoint = chosen["endpoint"]
        http_status = chosen["httpStatus"]

    return endpoint, error_timestamp, http_status


def _lookup_retry_logs(project, token, service, endpoint, error_timestamp, freshness):
    retry_filter = (
        f'resource.labels.service_name="{service}" '
        f'jsonPayload.message:"{endpoint}" '
        f'timestamp>="{error_timestamp}"'
    )
    retry_logs = logging_read(project, token, retry_filter, limit=30, freshness=freshness)
    return retry_filter, retry_logs


def _summarize_retry_logs(retry_logs):
    ok = 0
    fail = 0
    first_ok_timestamp = None
    for retry_log in reversed(retry_logs):
        payload = retry_log.get("jsonPayload", {})
        raw = payload.get("message", "") or retry_log.get("textPayload", "")
        message = strip_ansi(raw)
        if "200 OK" in message:
            ok += 1
            if first_ok_timestamp is None:
                first_ok_timestamp = retry_log.get("timestamp", "")[:23]
        elif "500" in message and "Internal Server Error" in message:
            fail += 1
    verdict = (
        "endpoint_healthy"
        if ok > 0
        else "still_failing"
        if fail > 0
        else "no_subsequent_requests"
    )
    return ok, fail, first_ok_timestamp, verdict


def _print_trace_error_result(as_json, result, message):
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return
    print(message)
    if message.startswith("**Cloud Logging query FAILED**"):
        print("Cannot determine if logs exist. Check auth and filter syntax.")


def cmd_trace(args):
    token = get_token()
    colors = _trace_colors()
    target = _lookup_error_group(args.project, token, args.group_id)
    result, first_line, known_service = _build_trace_result(args.group_id, target)

    if not args.json:
        _print_trace_header(args.group_id, target, known_service, colors)

    events = _load_recent_events(args.project, token, args.group_id)
    result["recentEvents"] = events
    if not args.json:
        _print_recent_events(events, colors)

    filt = _build_cloud_logging_filter(first_line, known_service)
    result["cloudLogging"] = {"filter": filt}
    if not args.json:
        print(f"\n{colors['bold']('### Cloud Logging Lookup')}\n")
        print(f"Filter: `{filt}`\n")

    try:
        lookup = _lookup_cloud_logging(args.project, token, filt, args.freshness)
    except LoggingError as exc:
        result["cloudLogging"]["error"] = str(exc)
        _print_trace_error_result(args.json, result, f"**Cloud Logging query FAILED**: {exc}")
        return

    if not lookup:
        result["cloudLogging"]["matched"] = False
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"No matching logs in Cloud Logging ({args.freshness} window).")
        return

    result["cloudLogging"].update(
        {
            "matched": True,
            "service": lookup["service"],
            "traceId": lookup["traceId"],
            "matchedEntries": lookup["matchedEntries"],
        }
    )
    if not args.json:
        print(f"- Service: {colors['bold'](lookup['service'])}")
        if lookup["traceId"]:
            print(f"- Cloud Trace ID: `{lookup['traceId']}`")
        else:
            print("- Cloud Trace ID: (not found)")
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
        _print_trace_error_result(args.json, result, f"\n**Cloud Logging trace query FAILED**: {exc}")
        return

    if trace_logs:
        lifecycle_entries = _build_lifecycle_entries(trace_logs)
        result["lifecycle"] = {
            "scope": "latest_event_only",
            "traceId": lookup["traceId"],
            "entries": lifecycle_entries,
        }
        if not args.json:
            _print_log_entries("### Request Lifecycle (trace-level match)", lifecycle_entries, colors)
    else:
        result["lifecycle"] = {
            "scope": "latest_event_only",
            "traceId": lookup["traceId"],
            "entries": [],
        }

    endpoint, error_timestamp, http_status = _extract_retry_context(trace_logs, lookup["logs"])
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
            print(f"- Error at: {error_timestamp[:23]}Z")
            print(f"- Verdict: {colors['yellow']('Error within success response')}")
            print(f"  Endpoint returned HTTP {http_status} but ERROR was logged internally.")
            print("  Retry check not applicable — the endpoint does not fail at HTTP level.")
        return

    if not args.json:
        print(f"\n{colors['bold']('### Retry Check')}\n")
        print(f"- Endpoint: `{endpoint}`")
        print(f"- Error at: {error_timestamp[:23]}Z")

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
        _print_trace_error_result(args.json, result, f"**Retry check query FAILED**: {exc}")
        return

    ok, fail, first_ok_timestamp, verdict = _summarize_retry_logs(retry_logs)
    result["retryCheck"] = {
        "scope": "endpoint",
        "endpoint": endpoint,
        "errorTimestamp": error_timestamp,
        "successCount": ok,
        "failureCount": fail,
        "firstSuccessTimestamp": first_ok_timestamp,
        "verdict": verdict,
    }

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    print(f"- After error: **{ok}** ok / **{fail}** fail")
    if ok > 0:
        print(f"- First success: {first_ok_timestamp}Z")
        print(
            f"- Verdict: {colors['green']('Likely recovered')} (endpoint-level match, not trace-level)"
        )
    elif fail > 0:
        print(
            f"- Verdict: {colors['red']('Not recovered')} (endpoint-level match, not trace-level)"
        )
    else:
        print(f"- Verdict: {colors['yellow']('Unknown')} (no subsequent requests on this endpoint)")
