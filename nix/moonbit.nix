{
  lib,
  stdenv,
  fetchurl,
}:

# nixpkgs has no MoonBit, so this pins the official release and its core library by hash.
# Keep the version and hashes in sync with scripts/install-agent-hooks.sh, which builds the agent-hooks command in cloud sessions.
stdenv.mkDerivation (attrs: {
  pname = "moonbit";
  version = "0.10.17+d971670cd";
  src = fetchurl {
    url = "https://cli.moonbitlang.com/binaries/${lib.escapeURL attrs.version}/moonbit-darwin-aarch64.tar.gz";
    hash = "sha256-OeAvdzBIbOpU0S6OeB2DpmXyRfamIdAeF6OhPxBOtDc=";
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
    platforms = [ "aarch64-darwin" ];
  };
})
