{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

# nixpkgs has no MoonBit, so this pins the official release and its core library by hash.
# Keep the version and hashes in sync with scripts/install-agent-hooks.sh, which builds the agent-hooks command in cloud sessions.
let
  releases = {
    aarch64-darwin = {
      archive = "darwin-aarch64";
      hash = "sha256-OeAvdzBIbOpU0S6OeB2DpmXyRfamIdAeF6OhPxBOtDc=";
    };
    # CI builds and tests dot-tools on Linux runners.
    x86_64-linux = {
      archive = "linux-x86_64";
      hash = "sha256-0Klur5HHfPzde333U5DFoaldC4oyixpe1v7gUM+/jVA=";
    };
  };
  release =
    releases.${stdenv.hostPlatform.system}
      or (throw "moonbit: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (
  attrs:
  {
    pname = "moonbit";
    version = "0.10.17+d971670cd";
    src = fetchurl {
      url = "https://cli.moonbitlang.com/binaries/${lib.escapeURL attrs.version}/moonbit-${release.archive}.tar.gz";
      inherit (release) hash;
    };
    core = fetchurl {
      url = "https://cli.moonbitlang.com/cores/core-${lib.escapeURL attrs.version}.tar.gz";
      hash = "sha256-LYN+y+9ZM8CXJtY2gqdpUSPWIuau4TUl+8mMS0lDNxQ=";
    };

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R bin lib include "$out/"
      chmod -R u+w "$out"
      # The archive drops the executable bits that the official installer sets again.
      chmod +x "$out"/bin/* "$out/bin/internal/tcc"
      tar xzf "$core" -C "$out/lib"
      # moon reads the toolchain and the bundled core from MOON_HOME.
      MOON_HOME="$out" MOON_CC="${stdenv.cc}/bin/cc" "$out/bin/moon" -C "$out/lib/core" bundle --warn-list -a --target native
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      MOON_HOME="$out" "$out/bin/moonc" -v | grep -F "v${attrs.version}"
      runHook postInstallCheck
    '';

    meta = {
      homepage = "https://www.moonbitlang.com/";
      platforms = builtins.attrNames releases;
    };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    # The Linux binaries link glibc and libgcc_s dynamically; patch them before the bundle step runs moon.
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    preInstall = ''
      autoPatchelf bin
    '';
  }
)
