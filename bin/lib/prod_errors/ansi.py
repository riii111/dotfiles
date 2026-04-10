import sys


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
        if not sys.stdout.isatty():
            return str(text)
        return f"{open_seq}{text}{_RESET}"

    return wrap


def col_widths(rows, headers):
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], len(str(cell)))
    return widths


def trunc(text, maxlen):
    text = str(text)
    if len(text) <= maxlen:
        return text
    return text[: maxlen - 1] + "\u2026"
