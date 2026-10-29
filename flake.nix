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
        # CVE-2026-111497: also rebuild shared-library and Python consumers.
        brotli = prev.brotli.overrideAttrs (attrs: _: {
          version = "1.2.1";
          src = final.fetchFromGitHub {
            owner = "google";
            repo = "brotli";
            tag = "v${attrs.version}";
            hash = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI=";
          };
        });
        # Rebuilding Brotli consumers also runs Node's worker-memory test.
        # Bound its worker count; the unchanged test fails at 11 workers on this Mac.
        nodejs-slim_24 = prev.nodejs-slim_24.overrideAttrs (attrs: {
          checkFlags = attrs.checkFlags ++ [ "JOBS=4" ];
        });
        go = final.go_1_27;
        buildGoModule = final.buildGo127Module;
        rustup = prev.rustup.overrideAttrs (
          attrs: _: {
            version = "1.29.2";
            src = final.fetchFromGitHub {
              owner = "rust-lang";
              repo = "rustup";
              tag = attrs.version;
              hash = "sha256-vtfZNMkUAmbdXv0sv7wdm62AjCkYJY188jLx8RrmO2M=";
            };
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit (attrs) pname version src;
              hash = "sha256-UL6nS3SbxKXFWftJLeFY622VQEyAimhNz+YJgZsLHJc=";
            };
          }
        );
        # Keep the patched verifier and managed-Python catalog in the official release.
        uv = final.stdenvNoCC.mkDerivation (attrs: {
          pname = "uv";
          version = "0.13.5";
          src = final.fetchurl {
            url = "https://releases.astral.sh/github/uv/releases/download/${attrs.version}/uv-aarch64-apple-darwin.tar.gz";
            hash = "sha256-dD+FA1oZluyzUGWeAc2frqlwmCm+CbG0sDxz6vPJzXM=";
          };
          nativeBuildInputs = [ final.installShellFiles ];
          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 uv "$out/bin/uv"
            install -Dm755 uvx "$out/bin/uvx"
            installShellCompletion --cmd uv \
              --bash <("$out/bin/uv" generate-shell-completion bash) \
              --fish <("$out/bin/uv" generate-shell-completion fish) \
              --zsh <("$out/bin/uv" generate-shell-completion zsh)
            runHook postInstall
          '';
          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            "$out/bin/uv" --version | grep -F "uv ${attrs.version} "
            runHook postInstallCheck
          '';
          meta = prev.uv.meta // { platforms = [ "aarch64-darwin" ]; };
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
      # The uninstaller evaluates a separate system; preserve the security overlay there too.
      securityDarwinTools =
        { pkgs, ... }:
        let
          source = pkgs.applyPatches {
            name = "nix-darwin-security-tools";
            src = nix-darwin;
            patches = [ ./darwin/uninstaller-pkgs.patch ];
          };
        in
        {
          # Replace the default tool with the same implementation using patched packages.
          system.tools.darwin-uninstaller.enable = false;
          environment.systemPackages = [
            (pkgs.callPackage "${source}/pkgs/darwin-uninstaller" { })
          ];
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
          # Patch ensurepip in a copied runtime; retain Nix Python's TLS backend and CA defaults.
          dailyPython = pkgs.stdenvNoCC.mkDerivation {
            pname = "python3";
            inherit (pkgs.python3) version;
            pipWheel = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl";
              hash = "sha256-/X9N+oGQ4BQBO58I8+lz9OTCb/0XmiBIlVM6clSBOnA=";
            };
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            dontStrip = true;
            dontPatchShebangs = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -R "${pkgs.python3}/." "$out/"
              chmod -R u+w "$out"
              ensurepip="$out/lib/python3.14/ensurepip"
              substituteInPlace "$ensurepip/__init__.py" \
                --replace-fail '_PIP_VERSION = "26.2.1"' '_PIP_VERSION = "26.2.2"'
              rm "$ensurepip/_bundled/pip-26.2.1-py3-none-any.whl"
              cp "$pipWheel" "$ensurepip/_bundled/pip-26.2.2-py3-none-any.whl"
              runHook postInstall
            '';
            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              "$out/bin/python3" -I -c 'import sys, ssl, sqlite3, ensurepip; assert ensurepip.__file__.startswith(sys.argv[1]); assert ensurepip.version() == "26.2.2"' "$out/"
              "$out/bin/python3" -I -m venv "$TMPDIR/verify-venv"
              "$TMPDIR/verify-venv/bin/python" -I -m pip --version | grep -F "pip 26.2.2 "
              runHook postInstallCheck
            '';
            meta = pkgs.python3.meta;
          };
          # Keep the security release and its patched bundled libraries together.
          dailyNode = pkgs.stdenvNoCC.mkDerivation (attrs: {
            pname = "nodejs";
            version = "24.22.1";
            src = pkgs.fetchurl {
              url = "https://nodejs.org/dist/v${attrs.version}/node-v${attrs.version}-darwin-arm64.tar.gz";
              hash = "sha256-icaCWT12zUQjP6U7FWMmTn3py7GJytFpE1xbT637wKc=";
            };
            dontConfigure = true;
            dontBuild = true;
            dontStrip = true;
            dontPatchShebangs = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -R bin include lib share "$out/"
              runHook postInstall
            '';
            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              test "$("$out/bin/node" --version)" = "v${attrs.version}"
              "$out/bin/node" "$out/lib/node_modules/npm/bin/npm-cli.js" --version
              runHook postInstallCheck
            '';
            meta = {
              homepage = "https://nodejs.org/";
              license = pkgs.lib.licenses.mit;
              platforms = [ "aarch64-darwin" ];
            };
          });
          cliTrust =
            let
              certificates = pkgs.cacert.override {
                blacklist = [
                  "Comodo AAA Services root"
                ];
              };
            in
            pkgs.runCommand "dotfiles-ca-certificates" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              bundle="${certificates}/etc/ssl/certs/ca-no-trust-rules-bundle.crt"
              python3 - "$bundle" <<'PY'
              import hashlib
              import pathlib
              import re
              import ssl
              import sys

              blocked = {
                  "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
                  "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
              }
              certificates = re.findall(
                  r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                  pathlib.Path(sys.argv[1]).read_text(), re.S,
              )
              if not certificates:
                  raise SystemExit("CA bundle is empty")
              for certificate in certificates:
                  fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(certificate)).hexdigest()
                  if fingerprint in blocked:
                      raise SystemExit(f"Blocked root remains in CA bundle: {fingerprint}")
              PY
              mkdir -p "$out/share/dotfiles"
              ln -s "$bundle" "$out/share/dotfiles/ca-bundle.crt"
            '';
          # Only this curl uses the verifier that blocks compromised intermediate keys.
          # rustls-ffi 0.15.6 pins rustls-webpki 0.103.16.
          curlRustlsFfi = pkgs.rustls-ffi.overrideAttrs (
            attrs: _: {
              version = "0.15.6";
              src = pkgs.fetchFromGitHub {
                owner = "rustls";
                repo = "rustls-ffi";
                tag = "v${attrs.version}";
                hash = "sha256-qVsadtAxS+yTt9FZMszwxql0CBTuz9ofpTto1hw9Kzg=";
              };
              cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
                inherit (attrs) pname version src;
                hash = "sha256-rALR92Ia+I2axVTMVjI9UyNiiS4e6QuN5QU9JfM0UY8=";
              };
            }
          );
          curlWithRustls = pkgs.curl.override {
            opensslSupport = false;
            rustlsSupport = true;
            http3Support = false; # rustls-ffi does not support QUIC yet.
            rustls-ffi = curlRustlsFfi;
          };
          dailyCurl =
            pkgs.runCommand "curl-${curlWithRustls.version}"
              {
                inherit (curlWithRustls) version;
                meta = curlWithRustls.meta // {
                  outputsToInstall = [ "out" ];
                };
                nativeBuildInputs = [ pkgs.makeWrapper ];
                passthru.rustlsFfi = curlRustlsFfi;
              }
              ''
                mkdir -p "$out/bin"
                # Plain PEM for rustls; do not inherit the installer's stale default bundle.
                makeWrapper "${pkgs.lib.getBin curlWithRustls}/bin/curl" "$out/bin/curl" \
                  --set-default CURL_CA_BUNDLE "${pkgs.cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt"
              '';
          mkVersionEntry = name: value: { inherit name value; };
          dailyCliPackages = with pkgs; [
            # Editor-integrated tooling that should exist in the normal shell too.
            _1password-cli
            bashInteractive
            nixd
            nixfmt
            dailyPython
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
            dailyCurl
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
            dailyNode
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
            paths = dailyCliPackages ++ [ cliTrust ];
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
            dailyCurl
            dailyNode
            dailyPython
            cliProfile
            cliTrust
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
          curl = cli.dailyCurl;
          python3 = cli.dailyPython;
          rustup = cli.pkgs.rustup;
          nodejs = cli.dailyNode;
          ca-certificates = cli.cliTrust;
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
              export SSL_CERT_FILE="${cli.cliTrust}/share/dotfiles/ca-bundle.crt"
              export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
              export CURL_CA_BUNDLE="$SSL_CERT_FILE"
              export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
              export PIP_CERT="$SSL_CERT_FILE"
              echo "Entered the dotfiles Nix shell."
            '';
          };

          # Only what `dotctl test` runs; the daily shell builds unfree tools like terraform from source in CI.
          # Take the tools from unpatched nixpkgs: the overlay's Brotli reaches rustc via curl, so git and ruff rebuild Rust.
          ci =
            let
              upstream = nixpkgs.legacyPackages.${system};
            in
            upstream.mkShell {
              packages = with upstream; [
                bashInteractive
                chezmoi
                git
                go_1_27
                jq
                cli.dailyPython
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
            securityDarwinTools
            ./darwin/hosts/personal.nix
          ];
        };

        work = nix-darwin.lib.darwinSystem {
          modules = [
            { nixpkgs.overlays = [ securityOverlay ]; }
            securityDarwinTools
            ./darwin/hosts/work.nix
          ];
        };
      };
    };
}
