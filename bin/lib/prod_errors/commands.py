import json
import sys
from datetime import datetime, timezone

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
    parse_since,
    period_timedelta_for,
    timed_count_duration_for_period,
)
from prod_errors.formatters import print_flat_summary, print_hotspots, print_service_summary
from prod_errors.logic import build_hotspot_data, build_service_summary_data, build_summary_data


def _summarize_log_entry(entry):
    payload = entry.get("jsonPayload", {})
    raw = payload.get("message", "") or entry.get("textPayload", "")
    return {
        "timestamp": entry.get("timestamp", ""),
        "severity": entry.get("severity", ""),
        "logger": payload.get("logger", ""),
        "message": strip_ansi(raw).split("\n")[0][:150],
    }


def _print_log_entries(title, entries, bold, dim, severity_color):
    if not entries:
        return
    print(f"\n{bold(title)}\n")
    for log_entry in entries:
        severity = log_entry["severity"]
        print(
            f"  [{log_entry['timestamp'][:23]}] "
            f"{severity_color.get(severity, color())(f'{severity:7s}')} "
            f"[{dim(log_entry['logger'])}] {log_entry['message']}"
        )


def cmd_summary(args):
    since = parse_since(args.since) if args.since else None
    token = get_token()
    groups = api_get_all_pages(build_group_stats_url(args.project), token, "errorGroupStats")
    statuses = {status.strip().upper() for status in args.status.split(",")}
    filtered = [
        group
        for group in groups
        if group["group"].get("resolutionStatus", "UNKNOWN") in statuses
    ]
    if since:
        filtered = [group for group in filtered if group.get("lastSeenTime", "") >= since]

    if args.group_by == "service":
        data = build_service_summary_data(filtered, since)
    else:
        data = build_summary_data(filtered, since)

    if args.json:
        result = {
            "project": args.project,
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "status": args.status,
            "period": f"since {since}" if since else "30 days",
            "total": len(filtered),
            "groupBy": args.group_by,
        }
        if args.group_by == "service":
            result["services"] = data
        else:
            result["errors"] = data
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    if not filtered:
        print(f"No errors with status [{args.status}] in the given time range.")
        return

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    period = f"since {since}" if since else "30 days"
    print(f"## {args.project} - Error Summary ({today})\n")
    print(f"Status: {args.status} | Period: {period} | Total: {len(filtered)}\n")
    if args.group_by == "service":
        print_service_summary(data)
    else:
        print_flat_summary(data, since)


def cmd_hotspots(args):
    if args.limit <= 0:
        print("--limit must be greater than 0", file=sys.stderr)
        sys.exit(1)

    since = parse_since(args.since) if args.since else None
    if since:
        window_begin = (
            datetime.now(timezone.utc) - period_timedelta_for(args.period)
        ).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        if since < window_begin:
            print(
                (
                    f"--since must be inside the selected --period window. "
                    f"For --period {args.period}, use {window_begin} or later."
                ),
                file=sys.stderr,
            )
            sys.exit(1)

    token = get_token()
    groups = api_get_all_pages(
        build_group_stats_url(
            args.project,
            period=args.period,
            timed_count_duration=timed_count_duration_for_period(args.period),
        ),
        token,
        "errorGroupStats",
    )
    statuses = {status.strip().upper() for status in args.status.split(",")}
    filtered = [
        group
        for group in groups
        if group["group"].get("resolutionStatus", "UNKNOWN") in statuses
    ]
    hotspots = build_hotspot_data(filtered, since)[: args.limit]

    if args.json:
        print(
            json.dumps(
                {
                    "project": args.project,
                    "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                    "status": args.status,
                    "period": args.period,
                    "since": since,
                    "limit": args.limit,
                    "total": len(hotspots),
                    "errors": hotspots,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return

    if not hotspots:
        print(f"No hotspot groups with status [{args.status}] in the selected window.")
        return

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    label = f"since {since}" if since else f"last {args.period}"
    print(f"## {args.project} - Error Hotspots ({today})\n")
    print(
        f"Status: {args.status} | Window: {label} | Limit: {args.limit} | Total: {len(hotspots)}\n"
    )
    print_hotspots(hotspots)


def cmd_trace(args):
    token = get_token()
    group_id = args.group_id
    project = args.project
    as_json = args.json

    bold = color(_BOLD)
    cyan = color(_CYAN)
    dim = color(_DIM)
    green = color(_GREEN)
    red = color(_RED)
    yellow = color(_YELLOW)
    severity_color = {
        "ERROR": color(_RED),
        "CRITICAL": color(_RED, _BOLD),
        "WARN": color(_YELLOW),
        "WARNING": color(_YELLOW),
        "INFO": color(_DIM),
        "DEBUG": color(_DIM),
    }

    groups = api_get_all_pages(build_group_stats_url(args.project), token, "errorGroupStats")
    target = next(
        (group for group in groups if group["group"].get("groupId") == group_id),
        None,
    )
    if not target:
        print(f"Error group {group_id} not found.", file=sys.stderr)
        sys.exit(1)

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

    if not as_json:
        print(f"{bold('## Error Group:')} {cyan(group_id)}\n")
        print(f"- Message: {first_line[:120]}")
        print(f"- Count: {target.get('count', '0')}")
        print(f"- First: {target.get('firstSeenTime', '')[:19]}Z")
        print(f"- Last:  {target.get('lastSeenTime', '')[:19]}Z")
        if known_service:
            print(f"- Service (from Error Reporting): {dim(known_service)}")

    event_data = api_get(
        f"{API_BASE}/projects/{project}/events"
        f"?groupId={group_id}&timeRange.period=PERIOD_30_DAYS&pageSize=5",
        token,
    )
    events = event_data.get("errorEvents", [])
    result["recentEvents"] = [
        {
            "eventTime": event.get("eventTime", ""),
            "service": event.get("serviceContext", {}).get("service", "unknown"),
        }
        for event in events
    ]

    if not as_json:
        print(f"\n{bold(f'### Recent Events ({len(events)})')}\n")
        for event in events:
            print(
                f"  - {event.get('eventTime', '')[:19]}Z | "
                f"{dim(event.get('serviceContext', {}).get('service', 'unknown'))}"
            )

    search = first_line[:80].replace('"', '\\"')
    if known_service:
        filt = f'resource.labels.service_name="{known_service}" "{search}" severity>=ERROR'
    else:
        filt = f'"{search}" severity>=ERROR'

    if not as_json:
        print(f"\n{bold('### Cloud Logging Lookup')}\n")
        print(f"Filter: `{filt}`\n")

    result["cloudLogging"] = {"filter": filt}

    try:
        logs = logging_read(project, token, filt, limit=3, freshness=args.freshness)
    except LoggingError as exc:
        result["cloudLogging"]["error"] = str(exc)
        _print_trace_error_result(as_json, result, f"**Cloud Logging query FAILED**: {exc}")
        return

    if not logs:
        result["cloudLogging"]["matched"] = False
        if as_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"No matching logs in Cloud Logging ({args.freshness} window).")
        return

    result["cloudLogging"]["matched"] = True
    entry = logs[0]
    resource_labels = entry.get("resource", {}).get("labels", {})
    service = resource_labels.get(
        "service_name", resource_labels.get("configuration_name", "unknown")
    )
    matched_logs = [_summarize_log_entry(log_entry) for log_entry in logs]
    trace_id = extract_trace_id(entry)
    result["cloudLogging"]["service"] = service
    result["cloudLogging"]["traceId"] = trace_id or None
    result["cloudLogging"]["matchedEntries"] = matched_logs

    if not as_json:
        print(f"- Service: {bold(service)}")
        print(f"- Cloud Trace ID: `{trace_id}`" if trace_id else "- Cloud Trace ID: (not found)")
        _print_log_entries(
            "### Matched Error Logs",
            list(reversed(matched_logs)),
            bold,
            dim,
            severity_color,
        )

    if not trace_id:
        if as_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print("\nCloud Trace ID was not found in the matched log entry.")
            print("Request-lifecycle lookup is unavailable, but the matched error logs above can be used to inspect this hotspot.")
        return

    trace_filter = f'resource.labels.service_name="{service}" jsonPayload.trace_id="{trace_id}"'
    try:
        trace_logs = logging_read(project, token, trace_filter, limit=50, freshness=args.freshness)
        if not trace_logs:
            trace_filter = (
                f'resource.labels.service_name="{service}" '
                f'trace="projects/{project}/traces/{trace_id}"'
            )
            trace_logs = logging_read(project, token, trace_filter, limit=50, freshness=args.freshness)
    except LoggingError as exc:
        result["lifecycle"] = {"error": str(exc)}
        _print_trace_error_result(as_json, result, f"\n**Cloud Logging trace query FAILED**: {exc}")
        return

    if trace_logs:
        lifecycle = []
        for trace_log in reversed(trace_logs):
            payload = trace_log.get("jsonPayload", {})
            lifecycle.append(
                {
                    "timestamp": trace_log.get("timestamp", ""),
                    "severity": trace_log.get("severity", ""),
                    "logger": payload.get("logger", ""),
                    "message": strip_ansi(
                        payload.get("message", "") or trace_log.get("textPayload", "")
                    ).split("\n")[0][:150],
                }
            )
        result["lifecycle"] = {
            "scope": "latest_event_only",
            "traceId": trace_id,
            "entries": lifecycle,
        }
        if not as_json:
            _print_log_entries(
                "### Request Lifecycle (trace-level match)",
                lifecycle,
                bold,
                dim,
                severity_color,
            )

    access_log_re = re.compile(
        r"(\d{3})\s+[\w ]+:\s+(GET|POST|PUT|PATCH|DELETE)\s+-\s+(.+?)\s+in\s+\d+ms"
    )
    endpoint = None
    error_timestamp = None
    http_status = None
    error_timestamps = []
    access_logs = []

    for trace_log in trace_logs:
        timestamp = trace_log.get("timestamp", "")
        severity = trace_log.get("severity", "")
        payload = trace_log.get("jsonPayload", {})
        raw = payload.get("message", "") or trace_log.get("textPayload", "")
        clean = strip_ansi(raw)
        if severity in ("ERROR", "CRITICAL"):
            error_timestamps.append(timestamp)
        match = access_log_re.search(clean)
        if match:
            access_logs.append(
                {
                    "timestamp": timestamp,
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

    if not endpoint or not error_timestamp:
        result["retryCheck"] = {"status": "could_not_extract_endpoint"}
        if as_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"\n{bold('### Retry Check')}\n")
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
        if as_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"\n{bold('### Retry Check')}\n")
            print(f"- Endpoint: `{endpoint}` (HTTP {http_status})")
            print(f"- Error at: {error_timestamp[:23]}Z")
            print(f"- Verdict: {yellow('Error within success response')}")
            print(f"  Endpoint returned HTTP {http_status} but ERROR was logged internally.")
            print("  Retry check not applicable — the endpoint does not fail at HTTP level.")
        return

    if not as_json:
        print(f"\n{bold('### Retry Check')}\n")
        print(f"- Endpoint: `{endpoint}`")
        print(f"- Error at: {error_timestamp[:23]}Z")

    retry_filter = (
        f'resource.labels.service_name="{service}" '
        f'jsonPayload.message:"{endpoint}" '
        f'timestamp>="{error_timestamp}"'
    )
    try:
        retry_logs = logging_read(project, token, retry_filter, limit=30, freshness=args.freshness)
    except LoggingError as exc:
        result["retryCheck"] = {"error": str(exc)}
        _print_trace_error_result(as_json, result, f"**Retry check query FAILED**: {exc}")
        return

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

    verdict = "endpoint_healthy" if ok > 0 else "still_failing" if fail > 0 else "no_subsequent_requests"
    result["retryCheck"] = {
        "scope": "endpoint",
        "endpoint": endpoint,
        "errorTimestamp": error_timestamp,
        "successCount": ok,
        "failureCount": fail,
        "firstSuccessTimestamp": first_ok_timestamp,
        "verdict": verdict,
    }

    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    print(f"- After error: **{ok}** ok / **{fail}** fail")
    if ok > 0:
        print(f"- First success: {first_ok_timestamp}Z")
        print(f"- Verdict: {green('Likely recovered')} (endpoint-level match, not trace-level)")
    elif fail > 0:
        print(f"- Verdict: {red('Not recovered')} (endpoint-level match, not trace-level)")
    else:
        print(f"- Verdict: {yellow('Unknown')} (no subsequent requests on this endpoint)")


def _print_trace_error_result(as_json, result, message):
    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(message)
        if message.startswith("**Cloud Logging query FAILED**"):
            print("Cannot determine if logs exist. Check auth and filter syntax.")
