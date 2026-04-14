import json
import sys
from datetime import datetime, timezone

from prod_errors.client import (
    api_get_all_pages,
    build_group_stats_url,
    get_token,
    parse_since,
    period_timedelta_for,
    timed_count_duration_for_period,
)
from prod_errors.formatters import (
    print_flat_summary,
    print_hotspots,
    print_service_summary,
)
from prod_errors.logic import (
    build_hotspot_data,
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
                    "date": current_jst_date(),
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

    today = current_jst_date()
    label = f"since {since}" if since else f"last {args.period}"
    print(f"## {args.project} - Error Hotspots ({today})\n")
    print(
        f"Status: {args.status} | Window: {label} | Limit: {args.limit} | Total: {len(hotspots)}\n"
    )
    print_hotspots(hotspots)


def cmd_trace(args):
    return trace_cmd(args)
