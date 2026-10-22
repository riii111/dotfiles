{ ... }:

{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  homebrew.onActivation.extraEnv.HOMEBREW_CURL_PATH = "/Users/a81803/.nix-profile/bin/curl";

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
