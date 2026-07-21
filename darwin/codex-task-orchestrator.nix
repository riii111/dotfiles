{
  codex-task-orchestrator,
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    escapeShellArgs
    getExe
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.codex-task-orchestrator;
  pollAll = pkgs.writeShellScript "codex-task-orchestrator-poll-all" ''
    status=0
    for orchestration_id in ${escapeShellArgs cfg.orchestrationIds}; do
      ${getExe cfg.package} poll "$orchestration_id" || status=$?
    done
    exit "$status"
  '';
in
{
  options.services.codex-task-orchestrator = {
    enable = mkEnableOption "periodic Codex task orchestration polling";

    package = mkOption {
      type = types.package;
      default = codex-task-orchestrator.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The codex-task-orchestrator package to run.";
    };

    orchestrationIds = mkOption {
      type = types.listOf (types.strMatching "^[a-z0-9][a-z0-9-]*$");
      default = [ ];
      description = "Orchestration IDs to poll sequentially.";
    };

    intervalSeconds = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Seconds between polling attempts.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.orchestrationIds != [ ];
        message = "services.codex-task-orchestrator.orchestrationIds must not be empty";
      }
      {
        assertion = lib.length cfg.orchestrationIds == lib.length (lib.unique cfg.orchestrationIds);
        message = "services.codex-task-orchestrator.orchestrationIds must not contain duplicates";
      }
    ];

    launchd.user.agents.codex-task-orchestrator = {
      command = pollAll;
      path = [
        cfg.package
        pkgs.gh
        "/usr/bin"
        "/bin"
      ];
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = cfg.intervalSeconds;
        ProcessType = "Background";
        StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/codex-task-orchestrator.log";
        StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/codex-task-orchestrator.log";
      };
    };
  };
}
