import re
from collections import defaultdict
from datetime import timedelta

from prod_errors.client import get_service_from_group
from prod_errors.timefmt import parse_timestamp


def find_related_groups(filtered):
    stack_trace_re = re.compile(r"^\s*at\s+")

    def full_msg(item):
        return item.get("representative", {}).get("message", "")

    def first_line(item):
        return full_msg(item).split("\n")[0]

    def service(item):
        return get_service_from_group(item) or ""

    def is_stack_line(line):
        return bool(stack_trace_re.match(line))

    def exception_class(message):
        match = re.search(r"([\w.]+(?:Exception|Error|Throwable))", message)
        return match.group(1) if match else None

    def times_overlap(a, b):
        a_first = a.get("firstSeenTime", "")[:16]
        a_last = a.get("lastSeenTime", "")[:16]
        b_first = b.get("firstSeenTime", "")[:16]
        b_last = b.get("lastSeenTime", "")[:16]
        if not all([a_first, a_last, b_first, b_last]):
            return False
        return a_first <= b_last and b_first <= a_last

    related = {}
    assigned = set()
    for i in range(len(filtered)):
        if i in assigned:
            continue
        for j in range(i + 1, len(filtered)):
            if j in assigned:
                continue
            if not service(filtered[i]) or service(filtered[i]) != service(filtered[j]):
                continue
            if not times_overlap(filtered[i], filtered[j]):
                continue

            exc_i = exception_class(full_msg(filtered[i]))
            exc_j = exception_class(full_msg(filtered[j]))
            stack_i = is_stack_line(first_line(filtered[i]))
            stack_j = is_stack_line(first_line(filtered[j]))
            if exc_i and exc_j:
                is_related = exc_i == exc_j
            elif stack_i and not exc_i and exc_j:
                is_related = True
            elif stack_j and not exc_j and exc_i:
                is_related = True
            else:
                is_related = False

            if not is_related:
                continue

            if stack_i and not stack_j:
                primary = j
                secondary = i
            else:
                primary = i
                secondary = j
            related[secondary] = primary + 1
            assigned.add(secondary)

    return related


def build_summary_data(filtered, since=None):
    related = find_related_groups(filtered)
    items = []
    for idx, item in enumerate(filtered):
        group = item["group"]
        entry = {
            "groupId": group.get("groupId", ""),
            "status": group.get("resolutionStatus", ""),
            "message": item.get("representative", {}).get("message", "").split("\n")[0],
            "count": int(item.get("count", "0")),
            "firstSeenTime": item.get("firstSeenTime", ""),
            "lastSeenTime": item.get("lastSeenTime", ""),
            "service": get_service_from_group(item) or None,
            "relatedTo": related.get(idx),
        }
        if since:
            first_seen = item.get("firstSeenTime", "")
            entry["isNew"] = first_seen >= since
            entry["isRegressed"] = first_seen < since
        items.append(entry)
    return items


def build_service_summary_data(filtered, since=None):
    by_service = defaultdict(list)
    for item in filtered:
        service = get_service_from_group(item) or "(unknown)"
        by_service[service].append(item)

    services = []
    for service, items in sorted(
        by_service.items(),
        key=lambda kv: sum(int(group.get("count", "0")) for group in kv[1]),
        reverse=True,
    ):
        top = sorted(
            items, key=lambda group: int(group.get("count", "0")), reverse=True
        )[:3]
        entry = {
            "service": service,
            "groupCount": len(items),
            "totalCount": sum(int(group.get("count", "0")) for group in items),
            "oldestFirstSeen": min(group.get("firstSeenTime", "") for group in items),
            "latestLastSeen": max(group.get("lastSeenTime", "") for group in items),
            "topErrors": [
                group.get("representative", {}).get("message", "").split("\n")[0][:80]
                for group in top
            ],
        }
        if since:
            entry["newCount"] = sum(
                1 for group in items if group.get("firstSeenTime", "") >= since
            )
            entry["regressedCount"] = sum(
                1 for group in items if group.get("firstSeenTime", "") < since
            )
        services.append(entry)
    return services


def int_or_zero(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def windowed_counts(item, since=None):
    timed_counts = item.get("timedCounts", [])
    if not timed_counts:
        count = int_or_zero(item.get("count", "0"))
        return count, (1 if count > 0 else 0), None, None

    total = 0
    active_buckets = 0
    first_bucket_start = None
    last_bucket_end = None
    for bucket in timed_counts:
        count = int_or_zero(bucket.get("count", "0"))
        if count <= 0:
            continue
        bucket_start = bucket.get("startTime", "")
        bucket_end = bucket.get("endTime", "")
        if since and bucket_end and bucket_end <= since:
            continue
        total += count
        active_buckets += 1
        if bucket_start and (
            first_bucket_start is None or bucket_start < first_bucket_start
        ):
            first_bucket_start = bucket_start
        if bucket_end and (last_bucket_end is None or bucket_end > last_bucket_end):
            last_bucket_end = bucket_end
    return total, active_buckets, first_bucket_start, last_bucket_end


def build_hotspot_data(filtered, since=None):
    related = find_related_groups(filtered)
    items = []
    for idx, item in enumerate(filtered):
        range_count, active_buckets, range_first, range_last = windowed_counts(
            item, since
        )
        if range_count <= 0:
            continue

        group = item["group"]
        items.append(
            {
                "groupId": group.get("groupId", ""),
                "status": group.get("resolutionStatus", ""),
                "message": item.get("representative", {})
                .get("message", "")
                .split("\n")[0],
                "count": range_count,
                "activeBuckets": active_buckets,
                "firstSeenTime": range_first or item.get("firstSeenTime", ""),
                "lastSeenTime": range_last or item.get("lastSeenTime", ""),
                "service": get_service_from_group(item) or None,
                "relatedGroupId": (
                    filtered[related[idx] - 1]["group"].get("groupId")
                    if idx in related
                    else None
                ),
            }
        )

    items.sort(
        key=lambda entry: (
            -entry["count"],
            -entry["activeBuckets"],
            -(
                int(
                    entry["lastSeenTime"]
                    .replace("-", "")
                    .replace(":", "")
                    .replace("T", "")
                    .replace("Z", "")
                    .replace(".", "")
                )
                if entry["lastSeenTime"]
                else 0
            ),
            entry["groupId"],
        )
    )

    rank_by_group_id = {
        entry["groupId"]: position for position, entry in enumerate(items, start=1)
    }
    for entry in items:
        related_group_id = entry.pop("relatedGroupId", None)
        entry["relatedTo"] = (
            rank_by_group_id.get(related_group_id) if related_group_id else None
        )
    return items


def bucket_timedelta_for(value):
    return {
        "1d": timedelta(days=1),
        "7d": timedelta(days=7),
    }[value]


def isoformat_utc(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def extract_log_group_ids(entry):
    return [
        group.get("id", "")
        for group in entry.get("errorGroups", [])
        if group.get("id", "")
    ]


def extract_log_message(entry):
    json_payload = entry.get("jsonPayload", {})
    if isinstance(json_payload.get("message"), str) and json_payload.get("message"):
        return json_payload["message"].split("\n")[0]
    if isinstance(entry.get("textPayload"), str) and entry.get("textPayload"):
        return entry["textPayload"].split("\n")[0]
    proto_payload = entry.get("protoPayload", {})
    if isinstance(proto_payload.get("status"), dict):
        message = proto_payload["status"].get("message", "")
        if isinstance(message, str) and message:
            return message.split("\n")[0]
    return ""


def extract_log_service(entry):
    resource = entry.get("resource", {})
    labels = resource.get("labels", {})
    if isinstance(labels, dict):
        for key in ("service_name", "module_id", "service"):
            value = labels.get(key, "")
            if value:
                return value
    json_payload = entry.get("jsonPayload", {})
    service_context = json_payload.get("serviceContext", {})
    if isinstance(service_context, dict):
        value = service_context.get("service", "")
        if value:
            return value
    return ""


def related_group_ids(filtered):
    related = find_related_groups(filtered)
    related_by_group_id = {}
    for idx, related_idx in related.items():
        group_id = filtered[idx]["group"].get("groupId", "")
        related_group_id = filtered[related_idx - 1]["group"].get("groupId", "")
        if group_id and related_group_id:
            related_by_group_id[group_id] = related_group_id
    return related_by_group_id


def aggregate_hotspot_logs(entries, since, until, bucket):
    since_dt = parse_timestamp(since)
    until_dt = parse_timestamp(until)
    bucket_span = bucket_timedelta_for(bucket)
    bucket_seconds = bucket_span.total_seconds()
    groups = {}

    for entry in entries:
        timestamp = parse_timestamp(entry.get("timestamp", ""))
        if timestamp is None or timestamp < since_dt or timestamp >= until_dt:
            continue
        group_ids = extract_log_group_ids(entry)
        if not group_ids:
            continue
        message = extract_log_message(entry)
        service = extract_log_service(entry)
        bucket_index = int((timestamp - since_dt).total_seconds() // bucket_seconds)

        for group_id in group_ids:
            group = groups.setdefault(
                group_id,
                {
                    "groupId": group_id,
                    "count": 0,
                    "firstSeenTime": None,
                    "lastSeenTime": None,
                    "message": "",
                    "service": "",
                    "bucketEventCounts": defaultdict(int),
                },
            )
            group["count"] += 1
            if group["firstSeenTime"] is None or timestamp < group["firstSeenTime"]:
                group["firstSeenTime"] = timestamp
            if group["lastSeenTime"] is None or timestamp > group["lastSeenTime"]:
                group["lastSeenTime"] = timestamp
            if message and not group["message"]:
                group["message"] = message
            if service and not group["service"]:
                group["service"] = service
            group["bucketEventCounts"][bucket_index] += 1

    return groups


def build_hotspot_analysis(
    aggregated_groups,
    group_metadata,
    prior_occurrences,
    since,
    until,
    bucket,
):
    since_dt = parse_timestamp(since)
    until_dt = parse_timestamp(until)
    bucket_span = bucket_timedelta_for(bucket)
    related_by_group_id = related_group_ids(list(group_metadata.values()))

    bucket_entries = []
    cursor = since_dt
    while cursor < until_dt:
        end = min(cursor + bucket_span, until_dt)
        bucket_entries.append(
            {
                "start": isoformat_utc(cursor),
                "end": isoformat_utc(end),
                "activeGroups": 0,
                "newGroups": 0,
                "recurringGroups": 0,
                "eventCount": 0,
            }
        )
        cursor = end

    errors = []
    for group_id, aggregated in aggregated_groups.items():
        metadata = group_metadata.get(group_id, {})
        group = metadata.get("group", {})
        representative = metadata.get("representative", {})
        is_recurring = prior_occurrences.get(group_id, False)
        is_new = not is_recurring
        bucket_counts = aggregated["bucketEventCounts"]
        entry = {
            "groupId": group_id,
            "status": group.get("resolutionStatus", "UNKNOWN"),
            "message": representative.get("message", "").split("\n")[0]
            or aggregated["message"],
            "count": aggregated["count"],
            "activeBuckets": len(bucket_counts),
            "firstSeenTime": isoformat_utc(aggregated["firstSeenTime"]),
            "lastSeenTime": isoformat_utc(aggregated["lastSeenTime"]),
            "service": get_service_from_group(metadata)
            or aggregated["service"]
            or None,
            "relatedGroupId": related_by_group_id.get(group_id),
            "isNewInRange": is_new,
            "isRecurringInRange": is_recurring,
            "bucketEventCounts": dict(bucket_counts),
        }
        errors.append(entry)

    errors.sort(
        key=lambda entry: (
            -entry["count"],
            -entry["activeBuckets"],
            -(
                int(
                    entry["lastSeenTime"]
                    .replace("-", "")
                    .replace(":", "")
                    .replace("T", "")
                    .replace("Z", "")
                    .replace(".", "")
                )
                if entry["lastSeenTime"]
                else 0
            ),
            entry["groupId"],
        )
    )

    rank_by_group_id = {
        entry["groupId"]: position for position, entry in enumerate(errors, start=1)
    }
    for entry in errors:
        related_group_id = entry.pop("relatedGroupId", None)
        entry["relatedTo"] = (
            rank_by_group_id.get(related_group_id) if related_group_id else None
        )
        bucket_counts = entry.pop("bucketEventCounts")
        for bucket_index, event_count in bucket_counts.items():
            if bucket_index >= len(bucket_entries):
                continue
            bucket_entry = bucket_entries[bucket_index]
            bucket_entry["activeGroups"] += 1
            bucket_entry["eventCount"] += event_count
            if entry["isNewInRange"]:
                bucket_entry["newGroups"] += 1
            if entry["isRecurringInRange"]:
                bucket_entry["recurringGroups"] += 1

    return {
        "summary": {
            "totalGroups": len(errors),
            "newGroups": sum(1 for entry in errors if entry["isNewInRange"]),
            "recurringGroups": sum(
                1 for entry in errors if entry["isRecurringInRange"]
            ),
            "eventCount": sum(entry["count"] for entry in errors),
        },
        "buckets": bucket_entries,
        "errors": errors,
    }
