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
      # CVE-2026-111943: rebuild Go CLIs, not just the compiler on PATH.
      securityOverlay = final: prev: {
        go = final.go_1_27;
        buildGoModule = final.buildGo127Module;
        # uv uses bundled Web PKI roots by default (GHSA-hq85-5cpj-mr62).
        uv = prev.uv.overrideAttrs (attrs: _: {
          version = "0.13.4";
          src = final.fetchFromGitHub {
            owner = "astral-sh";
            repo = "uv";
            tag = "0.13.4";
            hash = "sha256-US3SjwhWE3v4/i46YuBon2GA6PupC4Z0NRUqcV9CPLM=";
          };
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit (attrs) pname version src;
            hash = "sha256-9L47CTlkOVYfGuzE4e7e2FYAI192pAsipzzScF7B1j4=";
          };
        });
        # Nix's PEM consumers do not receive Firefox's OneCRL updates.
        cacert = prev.cacert.overrideAttrs (_: {
          version = "3.131.1";
          src = final.fetchurl {
            url = "https://raw.githubusercontent.com/nss-dev/nss/NSS_3_131_1_RTM/lib/ckfw/builtins/certdata.txt";
            hash = "sha256-PsK00kDcEsdH6vRQBh24SvdXxIO72jAvninOtdcL5RA=";
          };
        });
      };
      # This dotfiles repo is macOS-only for now, so keep the shell darwin-only too.
      systems = [
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      mkCli =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ securityOverlay ];
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "1password-cli"
                "terraform"
                "zsh-abbr"
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
            nixd
            nixfmt
            python3
            shellcheck
            shfmt
            stylua
            zig
            zls

            # Daily CLI tools owned by Nix.
            asdf-vm
            bat
            chezmoi
            csvlens
            delta
            direnv
            colima
            docker
            eza
            fd
            fzf
            gh
            ghq
            google-cloud-sdk
            git
            go
            golangci-lint
            gopls
            graphviz
            selectedGoTools
            jq
            lazygit
            lefthook
            neovim
            nix-direnv
            nodejs
            pgcli
            pngpaste
            pnpm
            postgresql_18
            pspg
            ripgrep
            rust-analyzer
            selectedRustupTools
            sqlfluff
            sqruff
            terraform
            tmux
            visidata
            wezterm.terminfo
            yq-go # Go implementation behind the `yq` command.
            zsh-abbr
            zsh-autosuggestions
            ruff
            uv
            herdr
          ];
          directToolVersions = nixpkgs.lib.concatMap (
            package:
            let
              name = nixpkgs.lib.getName package;
            in
            if
              builtins.elem name [
                "selected-go-tools"
                "selected-rustup-tools"
                "wezterm-terminfo"
              ]
            then
              [ ]
            else
              [ (mkVersionEntry name (package.version or "unknown")) ]
          ) dailyCliPackages;
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
          uv = cli.pkgs.uv;
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
            packages = cli.dailyCliPackages;

            shellHook = ''
              echo "Entered the dotfiles Nix shell."
            '';
          };

          # Only what `dotctl test` runs; the daily shell builds unfree tools like terraform from source in CI.
          ci = cli.pkgs.mkShell {
            packages = with cli.pkgs; [
              bashInteractive
              chezmoi
              git
              go
              jq
              python3
              ruff
            ];
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
            { nixpkgs.overlays = [ securityOverlay ]; }
            ./darwin/hosts/personal.nix
          ];
        };

        work = nix-darwin.lib.darwinSystem {
          modules = [
            { nixpkgs.overlays = [ securityOverlay ]; }
            ./darwin/hosts/work.nix
          ];
        };
      };
    };
}
