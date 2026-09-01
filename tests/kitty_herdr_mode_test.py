from pathlib import Path

from kitty.config import load_config
from kitty.fast_data_types import GLFW_MOD_CONTROL, GLFW_MOD_SHIFT, GLFW_MOD_SUPER
from kitty.utils import resolve_abs_or_config_path


repo_root = Path(__file__).resolve().parents[1]
config_path = repo_root / "private_dot_config/kitty/kitty.conf"
options = load_config(str(config_path))
assert options.window_logo_scale == 8.25

for kitty_config_path in config_path.parent.glob("*.conf"):
    assert "/Users/" not in kitty_config_path.read_text()

mode_names = {"herdr", "herdr-copy", "herdr-selection", "herdr-resize"}
assert mode_names <= options.keyboard_modes.keys()

for mode_name in mode_names:
    mode = options.keyboard_modes[mode_name]
    assert mode.on_unknown == "passthrough"
    assert mode.timeout == 0


def definitions(mode_name):
    mode = options.keyboard_modes[mode_name]
    return [definition for mappings in mode.keymap.values() for definition in mappings]


blur_toggle = [
    definition.definition
    for definition in definitions("")
    if "load-config" in definition.definition
]
assert blur_toggle == ["remote_control load-config kitty.conf blur-off.conf"]

blur_options = load_config(str(config_path), str(config_path.parent / "blur-off.conf"))
blur_definitions = [
    definition.definition
    for mappings in blur_options.keyboard_modes[""].keymap.values()
    for definition in mappings
    if "load-config" in definition.definition
]
assert blur_options.background_blur == 0
assert blur_definitions[-1] == "remote_control load-config kitty.conf"
assert resolve_abs_or_config_path("kitty.conf") == str(
    Path.home() / ".config/kitty/kitty.conf"
)

root_definitions = [definition.definition for definition in definitions("")]
assert "send_text all \\x7c" in root_definitions
assert root_definitions.count("send_text all \\x5c") == 2


def mapped_definitions(mods, key):
    return [
        definition.definition
        for parsed_key, mappings in options.keyboard_modes[""].keymap.items()
        if parsed_key.mods == mods and parsed_key.key == ord(key)
        for definition in mappings
    ]


assert (
    "combine : goto_layout splits : launch --location=vsplit --cwd=current"
    in mapped_definitions(GLFW_MOD_SUPER, "d")
)
assert (
    "combine : goto_layout splits : launch --location=hsplit --cwd=current"
    in mapped_definitions(GLFW_MOD_SUPER | GLFW_MOD_SHIFT, "d")
)
assert "toggle_layout stack" in mapped_definitions(GLFW_MOD_SUPER, "z")
assert "toggle_layout stack" not in mapped_definitions(
    GLFW_MOD_SUPER | GLFW_MOD_CONTROL, "z"
)

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
    "bottom-right",
    "--alpha",
    "0.30",
)
assert logo_actions[0].args[5] == str(Path.home() / ".config/kitty/herdr-logo.png")
assert logo_actions[1].func == "push_keyboard_mode"

logo_path = config_path.parent / "herdr-logo.png"
logo_data = logo_path.read_bytes()
assert logo_data.startswith(b"\x89PNG\r\n\x1a\n")
assert int.from_bytes(logo_data[16:20]) == 624
assert int.from_bytes(logo_data[20:24]) == 704
assert logo_data[25] == 6

print("kitty herdr mode test: ok")
