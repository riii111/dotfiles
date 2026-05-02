{
  description = "Nix CLI profile and dev shell for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nix-darwin,
      ...
    }:
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
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "zsh-abbr" ];
          };
          selectedGoTools = pkgs.runCommand "selected-go-tools" { } ''
            mkdir -p "$out/bin"
            for bin in goimports; do
              ln -s "${pkgs.gotools}/bin/$bin" "$out/bin/$bin"
            done
          '';
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
            chezmoi
            cmake
            csvlens
            delta
            deno
            direnv
            docker
            duti
            eza
            fd
            fzf
            gh
            ghq
            git
            gnupg
            go
            delve
            golangci-lint
            gopls
            selectedGoTools
            inetutils # Provides telnet.
            jq
            lazygit
            lefthook
            llvm
            neovim
            ninja
            nix-direnv
            openjdk
            pgcli
            pinentry_mac
            pngpaste
            pnpm
            postgresql_18
            pspg
            qemu
            ripgrep
            sccache
            sqlfluff
            sqls
            sqruff
            tmux
            tree
            visidata
            yq-go # Go implementation behind the `yq` command.
            zsh-abbr
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

      darwinConfigurations.riii111 = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin/configuration.nix
        ];
      };
    };
}
