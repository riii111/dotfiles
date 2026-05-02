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

  runAsUser =
    command:
    ''launchctl asuser "$(id -u -- ${user})" sudo --user=${user} --set-home -- env PATH=${escapeShellArg path} ${command}'';

  checkDependencies = runAsUser "sh -c ${escapeShellArg "for cmd in duti osacompile wezterm nvim csvlens vd; do if ! command -v \"$cmd\" >/dev/null; then echo \"skip default apps: $cmd is missing\" >&2; exit 1; fi; done"}";
in
{
  system.requiresPrimaryUser = [ "system.activationScripts.postActivation" ];

  system.activationScripts.postActivation.text = mkAfter ''
    echo >&2 "default apps..."
    if ${checkDependencies}; then
      ${runAsUser "${../scripts/build-open-apps.sh}"}
      ${runAsUser "${../scripts/setup-default-apps.sh}"}
    fi
  '';
}
