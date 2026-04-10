import sys

from prod_errors.ansi import (
    _BOLD,
    _CYAN,
    _DIM,
    _GREEN,
    _RED,
    _YELLOW,
    col_widths,
    color,
    pad_left,
    pad_right,
    trunc,
)


def _display_message(item):
    return item.get("message") or "(empty)"


def _display_service(item):
    return item.get("service") or "(unknown)"


def print_flat_summary(items, since=None):
    is_tty = sys.stdout.isatty()

    if not is_tty:
        header = "| # | Status | groupId | Error | Count | First | Last | Service | Related |"
        if since:
            header = "| # | Status | New? | groupId | Error | Count | First | Last | Service | Related |"
        print(header)
        print("-" * len(header))
        for idx, item in enumerate(items, 1):
            rel = f"→ #{item['relatedTo']}?" if item.get("relatedTo") else ""
            if since:
                mark = "NEW" if item["isNew"] else "REGR"
                print(
                    f"| {idx} | {item['status']} | {mark} | `{item['groupId']}` | {_display_message(item)[:80]} "
                    f"| {item['count']} | {item['firstSeenTime'][:10]} | {item['lastSeenTime'][:10]} "
                    f"| {_display_service(item)} | {rel} |"
                )
            else:
                print(
                    f"| {idx} | {item['status']} | `{item['groupId']}` | {_display_message(item)[:80]} "
                    f"| {item['count']} | {item['firstSeenTime'][:10]} | {item['lastSeenTime'][:10]} "
                    f"| {_display_service(item)} | {rel} |"
                )
        print("\n> Detail: `prod-errors trace <groupId>`")
        return

    status_color = {
        "OPEN": color(_RED),
        "ACKNOWLEDGED": color(_YELLOW),
        "RESOLVED": color(_GREEN),
    }
    gid_color = color(_CYAN)
    service_color = color(_DIM)
    header_color = color(_BOLD)
    new_color = color(_RED, _BOLD)
    regr_color = color(_YELLOW)
    rel_color = color(_DIM)

    rows = []
    for idx, item in enumerate(items, 1):
        rel = f"→ #{item['relatedTo']}?" if item.get("relatedTo") else ""
        if since:
            mark = "NEW" if item["isNew"] else "REGR"
            rows.append(
                (
                    str(idx),
                    item["status"],
                    mark,
                    item["groupId"],
                    trunc(_display_message(item), 50),
                    str(item["count"]),
                    item["firstSeenTime"][:10],
                    item["lastSeenTime"][:10],
                    trunc(_display_service(item), 40),
                    rel,
                )
            )
        else:
            rows.append(
                (
                    str(idx),
                    item["status"],
                    item["groupId"],
                    trunc(_display_message(item), 50),
                    str(item["count"]),
                    item["firstSeenTime"][:10],
                    item["lastSeenTime"][:10],
                    trunc(_display_service(item), 40),
                    rel,
                )
            )

    headers = (
        ("#", "Status", "New?", "groupId", "Error", "Count", "First", "Last", "Service", "Related")
        if since
        else ("#", "Status", "groupId", "Error", "Count", "First", "Last", "Service", "Related")
    )
    widths = col_widths(rows, headers)

    def render_row(cells, colorize=False):
        parts = []
        for idx, (cell, width) in enumerate(zip(cells, widths)):
            col_name = headers[idx]
            plain = str(cell)
            padded = pad_left(plain, width) if col_name == "Count" else pad_right(plain, width)
            if colorize:
                if col_name == "Status":
                    padded = status_color.get(plain, color())(pad_right(plain, width))
                elif col_name == "groupId":
                    padded = gid_color(pad_right(plain, width))
                elif col_name == "Service":
                    padded = service_color(pad_right(plain, width))
                elif col_name == "New?":
                    padded = new_color(pad_right(plain, width)) if plain == "NEW" else regr_color(pad_right(plain, width))
                elif col_name == "Related":
                    padded = rel_color(pad_right(plain, width))
                elif col_name == "Count":
                    padded = pad_left(plain, width)
                else:
                    padded = pad_right(plain, width)
            parts.append(padded)
        return " │ ".join(parts)

    sep = "─" * (sum(widths) + 3 * (len(widths) - 1))
    print(" │ ".join(header_color(pad_right(h, w)) for h, w in zip(headers, widths)))
    print(sep)
    for row in rows:
        print(render_row(row, colorize=True))
    print(sep)
    print("\nDetail: prod-errors trace <groupId>")


def print_service_summary(items):
    is_tty = sys.stdout.isatty()

    if not is_tty:
        print("| Service | Groups | Total Count | Oldest First | Latest Last | Top Errors |")
        print("|---------|--------|-------------|--------------|-------------|------------|")
        for item in items:
            print(
                f"| {item['service']} | {item['groupCount']} | {item['totalCount']} | "
                f"{item['oldestFirstSeen'][:10]} | {item['latestLastSeen'][:10]} | "
                f"{'; '.join(msg[:40] for msg in item['topErrors'])} |"
            )
        print("\n> Flat view: `prod-errors summary`")
        return

    service_color = color(_CYAN)
    header_color = color(_BOLD)
    dim_color = color(_DIM)
    rows = [
        (
            trunc(item["service"], 40),
            str(item["groupCount"]),
            str(item["totalCount"]),
            item["oldestFirstSeen"][:10],
            item["latestLastSeen"][:10],
            "; ".join(trunc(msg, 40) for msg in item["topErrors"]),
        )
        for item in items
    ]
    headers = ("Service", "Groups", "Total", "Oldest First", "Latest Last", "Top Errors")
    widths = col_widths(rows, headers)
    sep = "─" * (sum(widths) + 3 * (len(widths) - 1))
    print(" │ ".join(header_color(pad_right(h, w)) for h, w in zip(headers, widths)))
    print(sep)
    for row in rows:
        print(
            " │ ".join(
                [
                    service_color(pad_right(row[0], widths[0])),
                    pad_left(row[1], widths[1]),
                    pad_left(row[2], widths[2]),
                    pad_right(row[3], widths[3]),
                    pad_right(row[4], widths[4]),
                    dim_color(pad_right(row[5], widths[5])),
                ]
            )
        )
    print(sep)
    print("\nFlat view: prod-errors summary")


def print_hotspots(items):
    is_tty = sys.stdout.isatty()

    if not is_tty:
        print("| # | groupId | Error | Count | Days | First | Last | Service | Status | Related |")
        print("|---|---------|-------|-------|------|-------|------|---------|--------|---------|")
        for idx, item in enumerate(items, 1):
            rel = f"#{item['relatedTo']}?" if item.get("relatedTo") else ""
            print(
                f"| {idx} | `{item['groupId']}` | {_display_message(item)[:80]} | {item['count']} | "
                f"{item['activeDays']} | {item['firstSeenTime'][:10]} | {item['lastSeenTime'][:10]} | "
                f"{_display_service(item)} | {item['status']} | {rel} |"
            )
        return

    status_color = {
        "OPEN": color(_RED),
        "ACKNOWLEDGED": color(_YELLOW),
        "RESOLVED": color(_GREEN),
    }
    gid_color = color(_CYAN)
    service_color = color(_DIM)
    header_color = color(_BOLD)
    rel_color = color(_DIM)
    rows = [
        (
            str(idx),
            item["groupId"],
            trunc(_display_message(item), 48),
            str(item["count"]),
            str(item["activeDays"]),
            item["firstSeenTime"][:10],
            item["lastSeenTime"][:10],
            trunc(_display_service(item), 32),
            item["status"],
            f"#{item['relatedTo']}?" if item.get("relatedTo") else "",
        )
        for idx, item in enumerate(items, 1)
    ]
    headers = ("#", "groupId", "Error", "Count", "Days", "First", "Last", "Service", "Status", "Related")
    widths = col_widths(rows, headers)

    def render_row(cells, colorize=False):
        parts = []
        for idx, (cell, width) in enumerate(zip(cells, widths)):
            col_name = headers[idx]
            plain = str(cell)
            padded = pad_left(plain, width) if col_name in ("Count", "Days") else pad_right(plain, width)
            if colorize:
                if col_name == "groupId":
                    padded = gid_color(pad_right(plain, width))
                elif col_name == "Service":
                    padded = service_color(pad_right(plain, width))
                elif col_name == "Status":
                    padded = status_color.get(plain, color())(pad_right(plain, width))
                elif col_name == "Related":
                    padded = rel_color(pad_right(plain, width))
                elif col_name in ("Count", "Days"):
                    padded = pad_left(plain, width)
                else:
                    padded = pad_right(plain, width)
            parts.append(padded)
        return " │ ".join(parts)

    sep = "─" * (sum(widths) + 3 * (len(widths) - 1))
    print(" │ ".join(header_color(pad_right(h, w)) for h, w in zip(headers, widths)))
    print(sep)
    for row in rows:
        print(render_row(row, colorize=True))
    print(sep)
