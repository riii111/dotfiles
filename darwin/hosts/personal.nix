{ ... }:

{
  imports = [ ../common.nix ];

  system.primaryUser = "a81803";

  homebrew.casks = [
    "cursor"
    "emacs-app"
    "kitty"
  ];
}
