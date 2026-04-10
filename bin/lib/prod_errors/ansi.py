import sys
import unicodedata


_BOLD = "\033[1m"
_DIM = "\033[2m"
_RED = "\033[31m"
_YELLOW = "\033[33m"
_GREEN = "\033[32m"
_CYAN = "\033[36m"
_RESET = "\033[0m"


def color(*codes):
    open_seq = "".join(codes)

    def wrap(text):
        if not sys.stdout.isatty() or not open_seq:
            return str(text)
        return f"{open_seq}{text}{_RESET}"

    return wrap


def display_width(text):
    width = 0
    for char in str(text):
        if unicodedata.combining(char):
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width


def col_widths(rows, headers):
    widths = [display_width(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], display_width(cell))
    return widths


def trunc(text, maxlen):
    text = str(text)
    if display_width(text) <= maxlen:
        return text
    ellipsis = "\u2026"
    kept = []
    current_width = 0
    limit = maxlen - display_width(ellipsis)
    for char in text:
        char_width = display_width(char)
        if current_width + char_width > limit:
            break
        kept.append(char)
        current_width += char_width
    return "".join(kept) + ellipsis


def pad_left(text, width):
    text = str(text)
    return " " * max(width - display_width(text), 0) + text


def pad_right(text, width):
    text = str(text)
    return text + " " * max(width - display_width(text), 0)


def strip_ansi(text):
    import re

    return re.sub(r"\x1b\[[0-9;]*m", "", text)
