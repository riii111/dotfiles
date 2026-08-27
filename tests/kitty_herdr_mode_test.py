from pathlib import Path

from kitty.config import load_config


repo_root = Path(__file__).resolve().parents[1]
config_path = repo_root / "private_dot_config/kitty/kitty.conf"
options = load_config(str(config_path))

mode_names = {"herdr", "herdr-copy", "herdr-selection", "herdr-resize"}
assert mode_names <= options.keyboard_modes.keys()

for mode_name in mode_names:
    mode = options.keyboard_modes[mode_name]
    assert mode.on_unknown == "passthrough"
    assert mode.timeout == 0


def definitions(mode_name):
    mode = options.keyboard_modes[mode_name]
    return [definition for mappings in mode.keymap.values() for definition in mappings]


entry = [
    definition
    for definition in definitions("")
    if definition.options.when_focus_on == "title:^herdr"
    and definition.definition == "combine : herdr_logo_on : push_keyboard_mode herdr"
]
assert len(entry) == 1

main_definitions = {definition.definition for definition in definitions("herdr")}
assert "combine : herdr_logo_off : pop_keyboard_mode" in main_definitions
assert (
    "combine : send_key ctrl+; : send_key v : push_keyboard_mode herdr-copy"
    in main_definitions
)
assert (
    "combine : send_key ctrl+; : send_key r : push_keyboard_mode herdr-resize"
    in main_definitions
)

logo_actions = options.alias_map.resolve_aliases(
    "combine : herdr_logo_on : push_keyboard_mode herdr"
)
assert logo_actions[0].func == "remote_control"
assert logo_actions[0].args[:5] == (
    "set-window-logo",
    "--position",
    "top-right",
    "--alpha",
    "0.30",
)
assert logo_actions[1].func == "push_keyboard_mode"

logo_path = config_path.parent / "herdr-logo.png"
assert logo_path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")

print("kitty herdr mode test: ok")
