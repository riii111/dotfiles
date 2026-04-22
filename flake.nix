{
  description = "Nix CLI profile and dev shell for dotfiles";

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
      mkCli = system:
        let
          pkgs = import nixpkgs { inherit system; };
          cliPackages = with pkgs; [
            # Nix-native formatting and lint helpers.
            nil
            python3
            shellcheck
            shfmt
            taplo
            uv

            # Daily CLI tools owned by Nix.
            bat
            csvlens
            delta
            eza
            fd
            fzf
            gh
            ghq
            git
            jq
            k6
            lazygit
            lefthook
            mycli
            neovim
            pgcli
            pngpaste
            pspg
            ripgrep
            sqlfluff
            sqruff
            tmux
            tree
            visidata
            yq-go
            zsh-autosuggestions
          ];
          cliProfile = pkgs.buildEnv {
            name = "dotfiles-cli";
            paths = cliPackages;
            pathsToLink = [
              "/bin"
              "/share"
            ];
          };
        in
        {
          inherit pkgs cliPackages cliProfile;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          cli = mkCli system;
        in
        {
          cli = cli.cliProfile;
          default = cli.cliProfile;
        }
      );

      devShells = forAllSystems (
        system:
        let
          cli = mkCli system;
        in
        {
          default = cli.pkgs.mkShell {
            packages = [ cli.pkgs.alejandra cli.pkgs.bashInteractive ] ++ cli.cliPackages;

            shellHook = ''
              echo "Entered the dotfiles Nix shell."
            '';
          };
        }
      );
    };
}
