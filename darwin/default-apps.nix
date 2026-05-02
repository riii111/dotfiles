{ config, lib, ... }:

let
  inherit (lib) escapeShellArg mkAfter;

  user = escapeShellArg config.system.primaryUser;
  profile = "/Users/${config.system.primaryUser}/.nix-profile/bin";
  path = lib.concatStringsSep ":" [
    profile
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  runAsUser = command: ''
    launchctl asuser "$(id -u -- ${user})" sudo --user=${user} --set-home -- env PATH=${escapeShellArg path} ${command}
  '';
in
{
  system.requiresPrimaryUser = [ "system.activationScripts.postActivation" ];

  system.activationScripts.postActivation.text = mkAfter ''
    echo >&2 "default apps..."
    ${runAsUser "${../scripts/build-open-apps.sh}"}
    ${runAsUser "${../scripts/setup-default-apps.sh}"}
  '';
}
