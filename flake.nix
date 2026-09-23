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
          visidata = pkgs.visidata.overrideAttrs (old: {
            # Upstream tests need a writable home and must not share files across Nix builders.
            preCheck = (old.preCheck or "") + ''
              export HOME="$TMPDIR/visidata-home"
              mkdir -p "$HOME/Library/Application Support"
              cp -R tests/xdg/data/visidata "$HOME/Library/Application Support/visidata"
              substituteInPlace tests/test-vdx.sh \
                --replace-fail '/tmp/vd-nosave-output.txt' "$TMPDIR/vd-nosave-output.txt"
            '';
          });
          mdfriedKitty = pkgs.rustPlatform.buildRustPackage {
            inherit (pkgs.mdfried)
              pname
              version
              src
              cargoDeps
              meta
              ;
            buildNoDefaultFeatures = true;
            buildFeatures = [
              "svg"
              "mermaid"
            ];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
          };
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
            mdfriedKitty
            neovim
            nix-direnv
            nodejs
            pgcli
            pngpaste
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
          devShellOnlyPackages = with pkgs; [
            lua5_4
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
          ) (dailyCliPackages ++ devShellOnlyPackages);
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
