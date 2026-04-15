import json
import sys
from datetime import datetime, timezone

from prod_errors.client import (
    LoggingError,
    api_get_all_pages,
    api_get_optional,
    build_group_url,
    build_group_stats_url,
    get_token,
    logging_query,
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
    empty_hotspot_analysis,
    build_service_summary_data,
    build_summary_data,
    update_bucket_occurrence_labels,
)
from prod_errors.timefmt import current_jst_date, isoformat_utc, parse_timestamp
from prod_errors.trace import cmd_trace as trace_cmd

GROUP_METADATA_CHUNK_SIZE = 50
PRIOR_OCCURRENCE_CHUNK_SIZE = 20
PRIOR_OCCURRENCE_PAGE_SIZE = 200
PRIOR_OCCURRENCE_MAX_PAGES = 10


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
                    "total": analysis["summary"]["totalGroups"],
                    "shown": len(hotspots),
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
    until_dt_obj = (
        parse_timestamp(parse_time_arg(args.until, option_name="--until"))
        if args.until
        else now
    )

    if args.since:
        since_dt_obj = parse_timestamp(parse_since(args.since))
    else:
        since_dt_obj = until_dt_obj - period_timedelta_for(args.period)

    if since_dt_obj >= until_dt_obj:
        print("--since must be earlier than --until", file=sys.stderr)
        sys.exit(1)
    return isoformat_utc(since_dt_obj), isoformat_utc(until_dt_obj)


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
        print(f"hotspots data fetch failed: {e}", file=sys.stderr)
        sys.exit(1)

    aggregated_groups = aggregate_hotspot_logs(entries, since, until, bucket)
    if not aggregated_groups:
        return empty_hotspot_analysis(since, until, bucket)

    group_ids = sorted(aggregated_groups)
    try:
        group_metadata = _fetch_group_metadata(project, token, group_ids)
    except LoggingError as e:
        print(f"hotspots data fetch failed: {e}", file=sys.stderr)
        sys.exit(1)
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
    try:
        prior_occurrences = _find_prior_occurrences(
            project,
            token,
            filtered_group_ids,
            since,
        )
    except LoggingError as e:
        print(f"hotspots data fetch failed: {e}", file=sys.stderr)
        sys.exit(1)

    analysis = build_hotspot_analysis(
        filtered_groups,
        filtered_metadata,
        prior_occurrences,
        since,
        until,
        bucket,
    )
    update_bucket_occurrence_labels(analysis["buckets"])
    return analysis


def _fetch_group_metadata(project, token, group_ids):
    metadata = {}
    for index in range(0, len(group_ids), GROUP_METADATA_CHUNK_SIZE):
        chunk = group_ids[index : index + GROUP_METADATA_CHUNK_SIZE]
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
        missing_group_ids = [group_id for group_id in chunk if group_id not in metadata]
        for group_id in missing_group_ids:
            group = api_get_optional(
                build_group_url(project, group_id),
                token,
                allowed_statuses={404},
            )
            if not group:
                continue
            metadata[group_id] = {
                "group": group,
                "representative": {},
                "affectedServices": [],
            }
    return metadata


def _find_prior_occurrences(project, token, group_ids, since):
    prior_occurrences = {group_id: False for group_id in group_ids}
    for index in range(0, len(group_ids), PRIOR_OCCURRENCE_CHUNK_SIZE):
        chunk = group_ids[index : index + PRIOR_OCCURRENCE_CHUNK_SIZE]
        seen = set()
        page_token = None
        pages = 0
        filter_expr = " OR ".join(
            f'errorGroups.id="{_escape_logging_string(group_id)}"' for group_id in chunk
        )
        filt = f'({filter_expr}) AND timestamp<"{since}"'

        while len(seen) < len(chunk):
            pages += 1
            if pages > PRIOR_OCCURRENCE_MAX_PAGES:
                raise LoggingError(
                    f"prior occurrence lookup exceeded {PRIOR_OCCURRENCE_MAX_PAGES} pages; narrow the time range"
                )
            data = logging_query(
                project,
                token,
                filt,
                limit=PRIOR_OCCURRENCE_PAGE_SIZE,
                order_by="timestamp desc",
                page_token=page_token,
            )
            entries = data.get("entries", [])
            if not entries:
                break
            for entry in entries:
                for group in entry.get("errorGroups", []):
                    group_id = group.get("id", "")
                    if group_id in prior_occurrences:
                        seen.add(group_id)
                        prior_occurrences[group_id] = True
            page_token = data.get("nextPageToken")
            if not page_token:
                break
    return prior_occurrences


def _escape_logging_string(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')
