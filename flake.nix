{
  description = "Nix dev shell for dotfiles CLI and lint tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      # This dotfiles repo is macOS-only for now, so keep the shell darwin-only too.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # Nix-native formatting and lint helpers.
              alejandra
              bashInteractive
              nil
              python3
              shellcheck
              shfmt
              taplo
              uv

              # CLI tools kept in both Brew and Nix during additive rollout.
              bat
              delta
              eza
              fd
              fzf
              gh
              ghq
              git
              jq
              ripgrep
              tmux
              tree
              yq-go
            ];

            shellHook = ''
              echo "Entered the dotfiles Nix shell (CLI/lint tools only)."
            '';
          };
        }
      );
    };
}
