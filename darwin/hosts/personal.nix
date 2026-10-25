{ config, lib, ... }:

let
  user = lib.escapeShellArg config.system.primaryUser;
  home = "/Users/${config.system.primaryUser}";
  agent = lib.escapeShellArg "${home}/bin/affected-agent";
  agentPath = lib.escapeShellArg "${home}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin";
in
{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  # postActivation runs before /run/current-system points at the new system.
  system.activationScripts.script.text = lib.mkAfter ''
    if [[ -x ${agent} ]]; then
      /bin/launchctl asuser "$(/usr/bin/id -u -- ${user})" \
        /usr/bin/sudo --non-interactive --set-home --user=${user} -- \
        /usr/bin/env PATH=${agentPath} ${agent} after-apply >/dev/null 2>&1 || true
    fi
  '';

  homebrew.taps = [
    {
      name = "riii111/terraleph";
      trusted = true;
    }
  ];

  homebrew.brews = [
    "riii111/terraleph/terraleph"
  ];

  homebrew.casks = [
    "cursor"
    "emacs-app"
    "kitty"
  ];
}
