import configparser
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone


API_BASE = "https://clouderrorreporting.googleapis.com/v1beta1"
DEFAULT_LOGGING_PAGE_SIZE = 1000
DEFAULT_LOGGING_MAX_ENTRIES = 10000
DEFAULT_LOGGING_MAX_PAGES = 20


class LoggingError(Exception):
    pass


def get_token():
    cloudsdk_skip_prefixes = (
        "CLOUDSDK_AUTH_",
        "CLOUDSDK_CORE_ACCOUNT",
        "CLOUDSDK_CONFIG",
    )
    if any(k.startswith(p) for k in os.environ for p in cloudsdk_skip_prefixes):
        return _get_token_via_cli()
    try:
        gcloud_dir = os.path.expanduser("~/.config/gcloud")
        config_name = os.environ.get("CLOUDSDK_ACTIVE_CONFIG_NAME", "")
        if not config_name:
            active_config_path = os.path.join(gcloud_dir, "active_config")
            if os.path.exists(active_config_path):
                with open(active_config_path, encoding="utf-8") as f:
                    config_name = f.read().strip()
        config_name = config_name or "default"
        cfg = configparser.ConfigParser()
        cfg.read(os.path.join(gcloud_dir, "configurations", f"config_{config_name}"))
        if cfg.has_section("auth"):
            return _get_token_via_cli()
        account = cfg.get("core", "account", fallback="")
        if account:
            with sqlite3.connect(os.path.join(gcloud_dir, "access_tokens.db")) as conn:
                row = conn.execute(
                    "SELECT access_token, token_expiry FROM access_tokens WHERE account_id = ?",
                    (account,),
                ).fetchone()
            if row:
                expiry = datetime.strptime(row[1], "%Y-%m-%d %H:%M:%S.%f").replace(
                    tzinfo=timezone.utc
                )
                if expiry > datetime.now(timezone.utc) + timedelta(minutes=5):
                    return row[0]
    except Exception:
        pass
    return _get_token_via_cli()


def _get_token_via_cli():
    result = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"gcloud auth failed: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def api_get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:200]
        print(f"API error: HTTP {e.code} — {body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"API connection error: {e.reason}", file=sys.stderr)
        sys.exit(1)


def api_get_optional(url, token, allowed_statuses=None):
    allowed = set(allowed_statuses or [])
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code in allowed:
            return None
        body = e.read().decode("utf-8", errors="replace")[:200]
        raise LoggingError(f"HTTP {e.code} — {body}")
    except urllib.error.URLError as e:
        raise LoggingError(str(e.reason)[:200])


def api_get_all_pages(base_url, token, items_key):
    return api_get_all_pages_with_progress(base_url, token, items_key)


def api_get_all_pages_with_progress(base_url, token, items_key, progress=None):
    all_items = []
    url = base_url
    pages = 0
    while True:
        pages += 1
        data = api_get(url, token)
        all_items.extend(data.get(items_key, []))
        if progress:
            progress(page=pages, item_count=len(all_items))
        next_token = data.get("nextPageToken")
        if not next_token:
            break
        sep = "&" if "?" in base_url else "?"
        url = f"{base_url}{sep}pageToken={next_token}"
    return all_items


def logging_query(
    project,
    token,
    filt,
    limit=10,
    order_by="timestamp desc",
    freshness=None,
    page_token=None,
):
    full_filter = filt
    if freshness:
        match = re.match(r"^(\d+)d$", freshness)
        if not match:
            print(
                f"Invalid freshness format: '{freshness}' (expected Nd, e.g. 7d, 30d, 90d)",
                file=sys.stderr,
            )
            sys.exit(1)
        days = int(match.group(1))
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
        time_filter = cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")
        full_filter = f'{filt} timestamp>="{time_filter}"'

    body = {
        "resourceNames": [f"projects/{project}"],
        "filter": full_filter,
        "orderBy": order_by,
        "pageSize": limit,
    }
    if page_token:
        body["pageToken"] = page_token

    req = urllib.request.Request(
        "https://logging.googleapis.com/v2/entries:list",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise LoggingError(e.read().decode("utf-8", errors="replace")[:200])
    except urllib.error.URLError as e:
        raise LoggingError(str(e.reason)[:200])


def logging_read(project, token, filt, limit=10, freshness="30d"):
    data = logging_query(project, token, filt, limit=limit, freshness=freshness)
    return data.get("entries", [])


def logging_list_all(
    project,
    token,
    filt,
    limit=DEFAULT_LOGGING_PAGE_SIZE,
    order_by="timestamp asc",
    max_entries=DEFAULT_LOGGING_MAX_ENTRIES,
    max_pages=DEFAULT_LOGGING_MAX_PAGES,
    progress=None,
):
    entries = []
    page_token = None
    pages = 0
    while True:
        pages += 1
        data = logging_query(
            project,
            token,
            filt,
            limit=limit,
            order_by=order_by,
            page_token=page_token,
        )
        entries.extend(data.get("entries", []))
        if progress:
            progress(page=pages, item_count=len(entries))
        if len(entries) > max_entries:
            raise LoggingError(
                f"logging query returned more than {max_entries} entries; narrow the time range"
            )
        if pages > max_pages:
            raise LoggingError(
                f"logging query exceeded {max_pages} pages; narrow the time range"
            )
        page_token = data.get("nextPageToken")
        if not page_token:
            return entries


def logging_has_entries(project, token, filt):
    data = logging_query(project, token, filt, limit=1, order_by="timestamp desc")
    return bool(data.get("entries"))


def extract_trace_id(entry):
    json_payload = entry.get("jsonPayload", {})
    trace_id = json_payload.get("trace_id", "")
    if trace_id:
        return trace_id
    trace_field = entry.get("trace", "")
    if trace_field and "/traces/" in trace_field:
        return trace_field.split("/traces/")[-1]
    return ""


def get_service_from_group(item):
    for service in item.get("affectedServices", []):
        name = service.get("service", "")
        if name:
            return name
    return ""


def parse_time_arg(value, option_name="--since"):
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f%z"):
        try:
            dt = datetime.strptime(value, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        except ValueError:
            continue
    try:
        dt = datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError:
        pass
    print(f"Cannot parse {option_name} value: {value}", file=sys.stderr)
    sys.exit(1)


def parse_since(value):
    return parse_time_arg(value, option_name="--since")


def api_period_for(value):
    return {
        "1h": "PERIOD_1_HOUR",
        "6h": "PERIOD_6_HOURS",
        "1d": "PERIOD_1_DAY",
        "7d": "PERIOD_1_WEEK",
        "30d": "PERIOD_30_DAYS",
    }[value]


def timed_count_duration_for_period(value):
    return {
        "1h": "60s",
        "6h": "600s",
        "1d": "3600s",
        "7d": "21600s",
        "30d": "86400s",
    }[value]


def timed_count_duration_for_bucket(value):
    return {
        "1d": "86400s",
        "7d": "604800s",
    }[value]


def period_timedelta_for(value):
    return {
        "1h": timedelta(hours=1),
        "6h": timedelta(hours=6),
        "1d": timedelta(days=1),
        "7d": timedelta(days=7),
        "30d": timedelta(days=30),
    }[value]


def build_group_stats_url(
    project,
    period="30d",
    timed_count_duration=None,
    group_ids=None,
    order="COUNT_DESC",
    page_size=100,
):
    params = [("timeRange.period", api_period_for(period)), ("order", order)]
    if timed_count_duration:
        params.append(("timedCountDuration", timed_count_duration))
    if group_ids:
        params.extend(("groupId", group_id) for group_id in group_ids)
    if page_size:
        params.append(("pageSize", str(page_size)))
    return (
        f"{API_BASE}/projects/{project}/groupStats"
        f"?{urllib.parse.urlencode(params, doseq=True)}"
    )


def build_group_url(project, group_id):
    group_name = urllib.parse.quote(group_id, safe="")
    return f"{API_BASE}/projects/{project}/groups/{group_name}"
