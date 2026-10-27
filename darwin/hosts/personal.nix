{ config, lib, ... }:

let
  user = lib.escapeShellArg config.system.primaryUser;
  home = "/Users/${config.system.primaryUser}";
  agent = lib.escapeShellArg "${home}/bin/affected-agent";
  collector = lib.escapeShellArg "${home}/.local/bin/am-i-affected";
  agentPath = "${home}/.nix-profile/bin:${home}/.local/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin";
in
{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  launchd.user.agents.affected = {
    environment.PATH = agentPath;
    script = ''
      if [ -x ${collector} ]; then
        exec ${collector} collect-and-push </dev/null >/dev/null 2>&1
      fi
    '';
    serviceConfig = {
      Label = "local.am-i-affected";
      ProcessType = "Background";
      WorkingDirectory = home;
      StartCalendarInterval = builtins.genList (i: {
        Hour = i * 3;
        Minute = 0;
      }) 8;
    };
  };

  # postActivation runs before /run/current-system points at the new system.
  system.activationScripts.script.text = lib.mkAfter ''
    if [[ -x ${agent} ]]; then
      /bin/launchctl asuser "$(/usr/bin/id -u -- ${user})" \
        /usr/bin/sudo --non-interactive --set-home --user=${user} -- \
        /usr/bin/env PATH=${lib.escapeShellArg agentPath} ${agent} after-apply >/dev/null 2>&1 || true
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
