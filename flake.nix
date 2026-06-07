{
  description = "Nix CLI profile and dev shell for dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zigpkgs.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      zigpkgs,
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
          zigTools = import zigpkgs { inherit system; };
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "1password-cli"
                "terraform"
                "zsh-abbr"
              ];
            overlays = [
              (final: prev: {
                zig = zigTools.zig;
                zls = zigTools.zls;
                tbls = prev.tbls.overrideAttrs (old: rec {
                  version = "1.92.3";
                  src = prev.fetchFromGitHub {
                    owner = "k1LoW";
                    repo = "tbls";
                    rev = "v${version}";
                    hash = "sha256-/1yulnT+HDZGO8S8xk59sKXxoFaw5Hoa1XXAwp5z7eM=";
                  };
                  vendorHash = "sha256-DnXftqcjk2fKWytmqdg9eWjsofaOTsHOpxTeIbXqMlw=";
                });
              })
            ];
          };
          selectedGoTools = pkgs.runCommand "selected-go-tools" { } ''
            mkdir -p "$out/bin"
            for bin in goimports; do
              ln -s "${pkgs.gotools}/bin/$bin" "$out/bin/$bin"
            done
          '';
          selectedRustupTools = pkgs.runCommand "selected-rustup-tools" { } ''
            mkdir -p "$out/bin"
            for bin in cargo cargo-clippy cargo-fmt cargo-miri clippy-driver rls rust-gdb rust-gdbgui rust-lldb rustc rustdoc rustfmt rustup; do
              ln -s "${pkgs.rustup}/bin/$bin" "$out/bin/$bin"
            done
          '';
          mkVersionEntry = name: value: { inherit name value; };
          dailyCliPackages = with pkgs; [
            # Editor-integrated tooling that should exist in the normal shell too.
            _1password-cli
            bashInteractive
            nil
            nixd
            nixfmt
            python3
            shellcheck
            shfmt
            taplo
            zig
            zls

            # Daily CLI tools owned by Nix.
            asdf-vm
            bat
            chezmoi
            cmake
            csvlens
            delta
            deno
            direnv
            colima
            docker
            duti
            eza
            fd
            fzf
            gh
            ghq
            google-cloud-sdk
            git
            gnupg
            go
            delve
            golangci-lint
            gopls
            graphviz
            selectedGoTools
            inetutils # Provides telnet.
            jq
            k6
            lazygit
            lefthook
            llvm
            neovim
            ninja
            nix-direnv
            nodejs
            openjdk
            pgcli
            pinentry_mac
            pngpaste
            pnpm
            postgresql_18
            pspg
            qemu
            ripgrep
            rust-analyzer
            selectedRustupTools
            sccache
            sqlfluff
            sqls
            sqruff
            terraform
            tmux
            tree
            visidata
            wezterm.terminfo
            yq-go # Go implementation behind the `yq` command.
            zsh-abbr
            zsh-autosuggestions
            ruff
            tbls
            uv
          ];
          devShellOnlyPackages = with pkgs; [
            alejandra
          ];
          directToolVersions = nixpkgs.lib.concatMap
            (package:
              let
                name = nixpkgs.lib.getName package;
              in
              if builtins.elem name [
                "selected-go-tools"
                "selected-rustup-tools"
                "wezterm-terminfo"
              ] then
                [ ]
              else
                [ (mkVersionEntry name (package.version or "unknown")) ])
            (dailyCliPackages ++ devShellOnlyPackages);
          toolVersions = builtins.listToAttrs (
            directToolVersions
            ++ [
              (mkVersionEntry "goimports" pkgs.gotools.version)
              (mkVersionEntry "rustup shims" pkgs.rustup.version)
              (mkVersionEntry "wezterm-terminfo" pkgs.wezterm.version)
            ]
          );
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
            toolVersions
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

      lib.toolVersions = forAllSystems (
        system:
        let
          cli = mkCli system;
        in
        cli.toolVersions
      );

      darwinConfigurations = {
        personal = nix-darwin.lib.darwinSystem {
          modules = [
            ./darwin/hosts/personal.nix
          ];
        };

        work = nix-darwin.lib.darwinSystem {
          modules = [
            ./darwin/hosts/work.nix
          ];
        };
      };
    };
}
