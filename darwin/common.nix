{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

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
      NSAutomaticCapitalizationEnabled = true;
      NSAutomaticDashSubstitutionEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = true;
      NSAutomaticQuoteSubstitutionEnabled = true;
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
      "font-hack-nerd-font"
      "font-udev-gothic"
      "gcloud-cli"
      "ghostty"
      "homerow"
      "karabiner-elements"
      "keepassxc"
      "kiro"
      "temurin@11"
      "temurin@21"
      "wezterm"
      "wireshark-app"
      "zed"
    ];
  };

  system.stateVersion = 6;
}
