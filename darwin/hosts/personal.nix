{ config, lib, ... }:

let
  user = lib.escapeShellArg config.system.primaryUser;
  home = "/Users/${config.system.primaryUser}";
  agent = lib.escapeShellArg "${home}/bin/affected-agent";
  collector = lib.escapeShellArg "${home}/.local/bin/am-i-affected";
  agentPath = "${home}/.nix-profile/bin:${home}/.local/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin";
  agentService = command: settings: {
    environment.PATH = agentPath;
    script = ''
      if [ -x ${collector} ]; then
        exec ${collector} ${command}${
          lib.optionalString (command == "collect-and-push") " </dev/null >/dev/null 2>&1"
        }
      fi
    '';
    serviceConfig = {
      ProcessType = "Background";
      WorkingDirectory = home;
    }
    // settings;
  };
in
{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  launchd.user.agents = {
    affected = agentService "collect-and-push" {
      Label = "local.am-i-affected";
      StartCalendarInterval = builtins.genList (i: {
        Hour = i * 3;
        Minute = 0;
      }) 8;
    };
    affected-wake = agentService "watch-wake" {
      Label = "local.am-i-affected-wake";
      RunAtLoad = true;
      KeepAlive.Crashed = true;
      ThrottleInterval = 300;
      StandardErrorPath = "${home}/.am-i-affected-wake.log";
      Umask = 63;
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
