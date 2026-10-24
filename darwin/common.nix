{ config, ... }:

{
  imports = [
    ./keyboard-shortcuts.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.min-free = 30 * 1024 * 1024 * 1024;
  nix.settings.max-free = 50 * 1024 * 1024 * 1024;

  nix.gc = {
    automatic = true;
    interval = [
      {
        Hour = 3;
        Minute = 15;
      }
    ];
    options = "--delete-older-than 7d";
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

  # ~/.zshrc runs a cached compinit; the global one would run it a second time.
  programs.zsh.enableGlobalCompInit = false;

  security.pam.services.sudo_local.enable = false;

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

    CustomUserPreferences.NSGlobalDomain = {
      "com.apple.mouse.linear" = true;
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
    onActivation.cleanup = "none";
    # Under sudo, brew would read ~/.homebrew/trust.json instead of the shell's trust file.
    onActivation.extraEnv.XDG_CONFIG_HOME = "/Users/${config.system.primaryUser}/.config";
    onActivation.extraEnv.HOMEBREW_CURL_PATH = "/Users/${config.system.primaryUser}/.nix-profile/bin/curl";
    taps = [ "vjeantet/tap" ];
    # Notifications with an action menu for pr-wake review (github.com/riii111/pr-wake).
    brews = [ "vjeantet/tap/alerter" ];
    casks = [
      "codex"
      "font-droid-sans-mono-nerd-font"
      "font-udev-gothic"
      "ghostty"
      "karabiner-elements"
      "meetingbar"
      "wezterm@nightly"
      "wireshark-app"
    ];
  };

  system.stateVersion = 6;
}
