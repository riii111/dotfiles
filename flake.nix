{
  description = "Nix dev shell for dotfiles CLI and lint tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
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
              alejandra
              bashInteractive
              bat
              delta
              eza
              fd
              fzf
              gh
              ghq
              git
              jq
              nil
              ripgrep
              shellcheck
              shfmt
              taplo
              tmux
              tree
              uv
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
