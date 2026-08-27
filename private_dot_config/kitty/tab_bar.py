from pathlib import Path


SHELLS = {"bash", "dash", "fish", "nu", "sh", "zsh"}


def _working_directory_name(path: str) -> str:
    working_directory = Path(path)
    if working_directory == Path.home():
        return "~"
    return working_directory.name or "/"


def draw_title(data: dict) -> str:
    tab = data["tab"]
    executable = Path(tab.active_exe or "").name

    if executable in SHELLS and tab.active_wd:
        title = _working_directory_name(tab.active_wd)
    else:
        title = executable or data["title"]

    max_length = max(data["max_title_length"] - 2, 1)
    if len(title) > max_length:
        title = title[: max_length - 1] + "…"

    return f" {title} "
