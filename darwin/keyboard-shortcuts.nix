{ config, lib, ... }:

let
  inherit (lib) concatMapStrings concatStringsSep escapeShellArg mkAfter splitString;

  user = escapeShellArg config.system.primaryUser;
  asUser = ''launchctl asuser "$(id -u -- ${user})" sudo --user=${user} --'';

  # Match the bool and integer types System Settings writes; the old-style plist syntax would store strings.
  # Rewriting an entry, even with the same value, disables Spotlight's Show Apps until the next login, so only changed entries are written.
  writeShortcut =
    id: enabled: parameters:
    let
      enabledXml = if enabled == "1" then "<true/>" else "<false/>";
      parametersXml = concatMapStrings (p: "<integer>${p}</integer>") (splitString ", " parameters);
      entry = "<dict><key>enabled</key>${enabledXml}<key>value</key><dict><key>parameters</key><array>${parametersXml}</array><key>type</key><string>standard</string></dict></dict>";
      wanted = ''<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">${entry}</plist>'';
    in
    ''
      if [ "$(plutil -extract AppleSymbolicHotKeys.${id} xml1 -o - "$hotkeys" 2>/dev/null)" != "$(printf '%s' ${escapeShellArg wanted} | plutil -convert xml1 -o - -)" ]; then
        ${asUser} defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add ${id} ${escapeShellArg entry}
        hotkeysChanged=1
      fi
    '';

  shortcuts = [
    # Function-row shortcuts when F1-F12 are standard keys.
    (writeShortcut "7" "1" "65535, 120, 8650752")
    (writeShortcut "8" "1" "65535, 99, 8650752")
    (writeShortcut "9" "1" "65535, 118, 8650752")
    (writeShortcut "10" "1" "65535, 96, 8650752")
    (writeShortcut "11" "1" "65535, 97, 8650752")
    (writeShortcut "12" "1" "65535, 122, 8650752")
    (writeShortcut "13" "1" "65535, 98, 8650752")
    (writeShortcut "57" "1" "65535, 100, 8650752")
    (writeShortcut "59" "1" "65535, 96, 9437184")

    # Keyboard focus shortcuts.
    (writeShortcut "27" "1" "65535, 122, 9437184")
    (writeShortcut "15" "1" "56, 28, 1572864")
    (writeShortcut "17" "1" "61, 24, 1572864")
    (writeShortcut "19" "1" "45, 27, 1572864")
    (writeShortcut "21" "1" "56, 28, 1835008")
    (writeShortcut "23" "1" "92, 42, 1572864")
    (writeShortcut "25" "1" "46, 47, 1835008")
    (writeShortcut "26" "1" "44, 43, 1835008")

    # Mission Control and Spaces.
    (writeShortcut "32" "1" "65535, 126, 8650752")
    (writeShortcut "33" "1" "65535, 125, 8650752")
    (writeShortcut "34" "1" "65535, 126, 8781824")
    (writeShortcut "35" "1" "65535, 125, 8781824")
    (writeShortcut "36" "1" "65535, 103, 8388608")
    (writeShortcut "37" "1" "65535, 103, 8519680")
    (writeShortcut "79" "1" "65535, 123, 8650752")
    (writeShortcut "80" "1" "65535, 123, 8781824")
    (writeShortcut "81" "1" "65535, 124, 8650752")
    (writeShortcut "82" "1" "65535, 124, 8781824")

    # Screenshots, Spotlight, and Help.
    (writeShortcut "51" "1" "39, 50, 1572864")
    (writeShortcut "53" "1" "65535, 107, 8388608")
    (writeShortcut "54" "1" "65535, 113, 8388608")
    (writeShortcut "55" "1" "65535, 107, 8912896")
    (writeShortcut "56" "1" "65535, 113, 8912896")
    (writeShortcut "64" "0" "32, 49, 1048576")
    (writeShortcut "65" "1" "32, 49, 1572864")
    (writeShortcut "160" "1" "108, 37, 655360")
  ];
in
{
  system.requiresPrimaryUser = [ "system.activationScripts.postActivation" ];

  system.activationScripts.postActivation.text = mkAfter ''
    echo >&2 "keyboard shortcuts..."
    hotkeys=$(mktemp)
    hotkeysChanged=
    ${asUser} defaults export com.apple.symbolichotkeys - > "$hotkeys"
    ${concatStringsSep "\n" shortcuts}
    rm -f "$hotkeys"
    if [ -n "$hotkeysChanged" ]; then
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
      echo >&2 "keyboard shortcuts changed; restart the Mac to apply them"
    fi
  '';
}
