import re
from collections import defaultdict

from prod_errors.client import get_service_from_group


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
        top = sorted(items, key=lambda group: int(group.get("count", "0")), reverse=True)[
            :3
        ]
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
        if bucket_start and (first_bucket_start is None or bucket_start < first_bucket_start):
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
                "message": item.get("representative", {}).get("message", "").split("\n")[0],
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
            -(int(entry["lastSeenTime"].replace("-", "").replace(":", "").replace("T", "").replace("Z", "").replace(".", "")) if entry["lastSeenTime"] else 0),
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
