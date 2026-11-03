{
  lib,
  stdenv,
  fetchurl,
  git,
  moonbit,
}:

let
  # The checksum is the one the mooncakes registry index records for this version.
  async = fetchurl {
    url = "https://download.mooncakes.io/user/moonbitlang/async/0.22.5.zip";
    hash = "sha256-FCd2s/rDhbjul+YvsyE7AqgFla4aSoDt5kGfRS6rAcI=";
  };
  # moon resolves registry dependencies through the index even when the archive is cached, so the build gets an index with only the pinned entry.
  asyncIndexEntry = builtins.toJSON {
    name = "moonbitlang/async";
    version = "0.22.5";
    checksum = "142776b3fac385b8ee97e62fb3213b02a80595ae1a4a80ede6419f452eab01c2";
    source = "src";
    preferred_target = "native";
  };
in
stdenv.mkDerivation {
  pname = "agent-hooks";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./moon.mod
      ./cmd
      ./git_force
      ./git_trust
      ./github_comment
      ./github_tool
      ./permission
      ./pr_format
      ./pr_state
      ./shell
      ./statusline
      ./text
    ];
  };

  nativeBuildInputs = [ moonbit ];

  configurePhase = ''
    runHook preConfigure
    export MOON_HOME="$TMPDIR/moon-home"
    mkdir -p "$MOON_HOME/registry/index/user/moonbitlang" "$MOON_HOME/registry/cache/moonbitlang/async"
    ln -s ${moonbit}/bin ${moonbit}/lib ${moonbit}/include "$MOON_HOME/"
    printf '%s\n' ${lib.escapeShellArg asyncIndexEntry} > "$MOON_HOME/registry/index/user/moonbitlang/async.index"
    cp ${async} "$MOON_HOME/registry/cache/moonbitlang/async/0.22.5.zip"
    export MOON_CC="${stdenv.cc}/bin/cc"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    moon build --release --target native
    runHook postBuild
  '';

  doCheck = true;
  # The trust checks are tested against real Git checkouts.
  nativeCheckInputs = [ git ];
  checkPhase = ''
    runHook preCheck
    moon fmt --check
    moon check --target native --deny-warn
    moon test --target native
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 _build/native/release/build/cmd/main/main.exe "$out/bin/agent-hooks"
    install -Dm755 _build/native/release/build/cmd/codex_read_lines/codex_read_lines.exe "$out/bin/codex-read-lines"
    install -Dm755 _build/native/release/build/cmd/codex_force_with_lease/codex_force_with_lease.exe "$out/bin/codex-force-with-lease"
    install -Dm755 _build/native/release/build/cmd/claude_statusline/claude_statusline.exe "$out/bin/claude-statusline"
    runHook postInstall
  '';

  meta.platforms = [ "aarch64-darwin" ];
}
