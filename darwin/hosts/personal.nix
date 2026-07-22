{ ... }:

{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  homebrew.casks = [
    "cursor"
    "zed"
  ];

  services.codex-task-orchestrator = {
    enable = true;
    orchestrationIds = [ "codex-task-orchestration" ];
    intervalSeconds = 180;
  };
}
