from datetime import datetime, timezone
from zoneinfo import ZoneInfo


JST = ZoneInfo("Asia/Tokyo")


def now_utc():
    return datetime.now(timezone.utc)


def current_jst_date():
    return now_utc().astimezone(JST).strftime("%Y-%m-%d")


def parse_timestamp(value):
    if not value:
        return None
    normalized = str(value).strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def isoformat_utc(value):
    parsed = value if isinstance(value, datetime) else parse_timestamp(value)
    if parsed is None:
        return ""
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def format_jst_timestamp(value, include_seconds=False, include_millis=False):
    parsed = parse_timestamp(value)
    if parsed is None:
        return ""
    local = parsed.astimezone(JST)
    text = local.strftime("%Y-%m-%d %H:%M")
    if include_millis:
        include_seconds = True
    if include_seconds:
        text += local.strftime(":%S")
    if include_millis:
        text += f".{local.microsecond // 1000:03d}"
    return f"{text} JST"


def format_relative_age(value, now=None):
    parsed = parse_timestamp(value)
    if parsed is None:
        return ""
    current = now or now_utc()
    seconds = max(int((current - parsed).total_seconds()), 0)
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def format_summary_last_seen(value, now=None):
    absolute = format_jst_timestamp(value)
    if not absolute:
        return ""
    relative = format_relative_age(value, now=now)
    return f"{absolute} ({relative})" if relative else absolute
