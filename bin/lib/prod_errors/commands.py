import json
import sys
from datetime import datetime, timezone

from prod_errors.client import (
    LoggingError,
    api_get_all_pages,
    build_group_stats_url,
    get_token,
    logging_has_entries,
    logging_list_all,
    parse_time_arg,
    parse_since,
    period_timedelta_for,
)
from prod_errors.formatters import (
    print_flat_summary,
    print_hotspots,
    print_hotspot_bucket_summary,
    print_hotspot_overview,
    print_service_summary,
)
from prod_errors.logic import (
    aggregate_hotspot_logs,
    build_hotspot_analysis,
    build_service_summary_data,
    build_summary_data,
)
from prod_errors.timefmt import current_jst_date
from prod_errors.trace import cmd_trace as trace_cmd


def cmd_summary(args):
    since = parse_since(args.since) if args.since else None
    token = get_token()
    groups = api_get_all_pages(
        build_group_stats_url(args.project), token, "errorGroupStats"
    )
    statuses = {status.strip().upper() for status in args.status.split(",")}
    filtered = [
        group
        for group in groups
        if group["group"].get("resolutionStatus", "UNKNOWN") in statuses
    ]
    if since:
        filtered = [
            group for group in filtered if group.get("lastSeenTime", "") >= since
        ]

    if args.group_by == "service":
        data = build_service_summary_data(filtered, since)
    else:
        data = build_summary_data(filtered, since)

    if args.json:
        result = {
            "project": args.project,
            "date": current_jst_date(),
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

    today = current_jst_date()
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

    since, until = _resolve_hotspot_window(args)
    token = get_token()
    statuses = {status.strip().upper() for status in args.status.split(",")}
    analysis = _build_hotspot_range_analysis(
        args.project,
        token,
        since,
        until,
        args.bucket,
        statuses,
    )
    hotspots = analysis["errors"][: args.limit]

    if args.json:
        print(
            json.dumps(
                {
                    "project": args.project,
                    "date": current_jst_date(),
                    "status": args.status,
                    "period": args.period,
                    "since": since,
                    "until": until,
                    "bucket": args.bucket,
                    "limit": args.limit,
                    "total": len(hotspots),
                    "summary": analysis["summary"],
                    "buckets": analysis["buckets"],
                    "errors": hotspots,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return

    if not analysis["errors"]:
        print(f"No hotspot groups with status [{args.status}] in the selected window.")
        return

    today = current_jst_date()
    label = f"{since} -> {until}"
    print(f"## {args.project} - Error Hotspots ({today})\n")
    print(
        f"Status: {args.status} | Window: {label} | Bucket: {args.bucket} | Limit: {args.limit} | Shown: {len(hotspots)}/{analysis['summary']['totalGroups']}\n"
    )
    print_hotspot_overview(analysis["summary"])
    print()
    print_hotspot_bucket_summary(analysis["buckets"])
    print()
    print("Hotspot Ranking")
    print_hotspots(hotspots)


def cmd_trace(args):
    return trace_cmd(args)


def _resolve_hotspot_window(args):
    now = datetime.now(timezone.utc)
    until_dt = (
        parse_time_arg(args.until, option_name="--until")
        if args.until
        else isoformat_utc(now)
    )
    until_dt_obj = datetime.strptime(until_dt, "%Y-%m-%dT%H:%M:%S.%fZ").replace(
        tzinfo=timezone.utc
    )

    if args.since:
        since = parse_since(args.since)
    else:
        since = (until_dt_obj - period_timedelta_for(args.period)).strftime(
            "%Y-%m-%dT%H:%M:%S.%fZ"
        )

    if since >= until_dt:
        print("--since must be earlier than --until", file=sys.stderr)
        sys.exit(1)
    return since, until_dt


def _build_hotspot_range_analysis(project, token, since, until, bucket, statuses):
    try:
        entries = logging_list_all(
            project,
            token,
            f'errorGroups.id:* AND timestamp>="{since}" AND timestamp<"{until}"',
            limit=1000,
            order_by="timestamp asc",
        )
    except LoggingError as e:
        print(f"Cloud Logging query failed: {e}", file=sys.stderr)
        sys.exit(1)

    aggregated_groups = aggregate_hotspot_logs(entries, since, until, bucket)
    if not aggregated_groups:
        return {"summary": {}, "buckets": [], "errors": []}

    group_ids = sorted(aggregated_groups)
    group_metadata = _fetch_group_metadata(project, token, group_ids)
    filtered_group_ids = [
        group_id
        for group_id in group_ids
        if group_metadata.get(group_id, {})
        .get("group", {})
        .get("resolutionStatus", "UNKNOWN")
        in statuses
    ]
    filtered_groups = {
        group_id: aggregated_groups[group_id] for group_id in filtered_group_ids
    }
    filtered_metadata = {
        group_id: group_metadata[group_id]
        for group_id in filtered_group_ids
        if group_id in group_metadata
    }
    prior_occurrences = {}
    for group_id in filtered_group_ids:
        try:
            prior_occurrences[group_id] = logging_has_entries(
                project,
                token,
                f'errorGroups.id="{_escape_logging_string(group_id)}" AND timestamp<"{since}"',
            )
        except LoggingError as e:
            print(f"Cloud Logging query failed: {e}", file=sys.stderr)
            sys.exit(1)

    return build_hotspot_analysis(
        filtered_groups,
        filtered_metadata,
        prior_occurrences,
        since,
        until,
        bucket,
    )


def _fetch_group_metadata(project, token, group_ids):
    metadata = {}
    for index in range(0, len(group_ids), 50):
        chunk = group_ids[index : index + 50]
        groups = api_get_all_pages(
            build_group_stats_url(
                project,
                period="30d",
                group_ids=chunk,
                page_size=max(len(chunk), 1),
            ),
            token,
            "errorGroupStats",
        )
        for group in groups:
            group_id = group.get("group", {}).get("groupId", "")
            if group_id:
                metadata[group_id] = group
    return metadata


def _escape_logging_string(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def isoformat_utc(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
