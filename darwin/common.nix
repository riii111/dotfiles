{ ... }:

{
  imports = [
    ./default-apps.nix
    ./keyboard-shortcuts.nix
    ./mouse.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    interval = [
      {
        Weekday = 7;
        Hour = 3;
        Minute = 15;
      }
    ];
    options = "--delete-older-than 30d";
  };

  nix.optimise = {
    automatic = true;
    interval = [
      {
        Weekday = 7;
        Hour = 4;
        Minute = 15;
      }
    ];
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.defaults = {
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.keyboard.fnState" = true;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
    };

    dock = {
      autohide = true;
      show-recents = false;
    };

    finder = {
      ShowPathbar = true;
      ShowStatusBar = true;
    };
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "check";
    casks = [
      "codex"
      "font-droid-sans-mono-nerd-font"
      "ghostty"
      "karabiner-elements"
      "temurin@21"
      "wezterm"
      "wireshark-app"
      "zed"
    ];
  };

  system.stateVersion = 6;
}
