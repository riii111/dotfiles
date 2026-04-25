{
  description = "Nix CLI profile and dev shell for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      # This dotfiles repo is macOS-only for now, so keep the shell darwin-only too.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      mkCli =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          dailyCliPackages = with pkgs; [
            # Editor-integrated tooling that should exist in the normal shell too.
            nil
            nixd
            nixfmt
            python3
            shellcheck
            shfmt
            taplo

            # Daily CLI tools owned by Nix.
            bat
            cmake
            csvlens
            delta
            deno
            direnv
            docker
            eza
            fd
            fzf
            gemini-cli
            gh
            ghq
            git
            go
            golangci-lint
            inetutils # Provides telnet.
            jq
            k6
            lazygit
            lefthook
            llvm
            mycli
            neovim
            ninja
            pgcli
            pngpaste
            pnpm
            pspg
            ripgrep
            sccache
            sqlfluff
            sqruff
            tmux
            tree
            visidata
            yq-go # Go implementation behind the `yq` command.
            zsh-autosuggestions
          ];
          devShellOnlyPackages = with pkgs; [
            alejandra
            bashInteractive
            uv
          ];
          cliProfile = pkgs.buildEnv {
            name = "dotfiles-cli";
            paths = dailyCliPackages;
            pathsToLink = [
              "/bin"
              "/share"
            ];
          };
        in
        {
          inherit
            pkgs
            dailyCliPackages
            devShellOnlyPackages
            cliProfile
            ;
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
            packages = cli.devShellOnlyPackages ++ cli.dailyCliPackages;

            shellHook = ''
              echo "Entered the dotfiles Nix shell."
            '';
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          cli = mkCli system;
        in
        cli.pkgs.nixfmt-tree
      );
    };
}
