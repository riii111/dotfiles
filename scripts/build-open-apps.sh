#!/usr/bin/env bash
set -euo pipefail

# Build .app wrappers that forward Finder "Open" events to WezTerm running
# nvim / vd / csvlens. Installs under ~/Library/Application Support/ so the
# wrappers stay out of Launchpad, and re-registers with LaunchServices so duti
# can target them by bundle ID.
#
# Idempotent: re-running overwrites existing installs.

readonly DEST="$HOME/Library/Application Support/open-routing"
readonly WEZTERM="/opt/homebrew/bin/wezterm"
readonly NVIM="/opt/homebrew/bin/nvim"
readonly VD="/opt/homebrew/bin/vd"
readonly CSVLENS="/opt/homebrew/bin/csvlens"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

[[ -x "$WEZTERM" ]] || { echo "ERROR: $WEZTERM not found (brew install --cask wezterm)"; exit 1; }
[[ -x "$NVIM" ]] || { echo "ERROR: $NVIM not found (brew install neovim)"; exit 1; }
[[ -x "$VD" ]] || { echo "ERROR: $VD not found (brew install visidata)"; exit 1; }
[[ -x "$CSVLENS" ]] || { echo "ERROR: $CSVLENS not found (brew install csvlens)"; exit 1; }
command -v osacompile >/dev/null || { echo "ERROR: osacompile missing"; exit 1; }

mkdir -p "$DEST"

WORK="$(mktemp -d -t open-apps.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

build_app() {
	local name="$1" bundle_id="$2" cmd="$3"
	local src="$WORK/${name}.applescript"
	local staged="$WORK/${name}.app"
	local dst="$DEST/${name}.app"

	# Prefer `wezterm cli spawn --new-window` so the file opens as a new window
	# inside the running WezTerm (no Dock duplication). Fall back to `wezterm start`
	# when no mux server is running (cold start).
	cat >"$src" <<APPLESCRIPT
on open theFiles
	set fileList to ""
	repeat with f in theFiles
		set fileList to fileList & space & quoted form of POSIX path of f
	end repeat
	do shell script "${WEZTERM} cli spawn --new-window -- ${cmd}" & fileList & " >/dev/null 2>&1 || ${WEZTERM} start -- ${cmd}" & fileList & " >/dev/null 2>&1 &"
end open

on run
	do shell script "${WEZTERM} cli spawn --new-window -- ${cmd} >/dev/null 2>&1 || ${WEZTERM} start -- ${cmd} >/dev/null 2>&1 &"
end run
APPLESCRIPT

	osacompile -o "$staged" "$src"

	local plist="$staged/Contents/Info.plist"
	# osacompile doesn't set CFBundleIdentifier; add it, fall back to set if it ever appears.
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_id}" "$plist" 2>/dev/null || \
		/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_id}" "$plist"
	/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist" 2>/dev/null || \
		/usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$plist"
	/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$plist" 2>/dev/null || true

	if [[ -d "$dst" ]]; then
		rm -rf "$dst"
	fi
	cp -R "$staged" "$dst"

	"$LSREGISTER" -f "$dst"
	echo "Built: $dst ($bundle_id)"
}

build_app "OpenInNvim" "com.riii111.openinnvim" "$NVIM"
build_app "OpenInCsvLens" "com.riii111.openincsvlens" "$CSVLENS -d auto"
build_app "OpenInVisiData" "com.riii111.openinvisidata" "$VD"

cat <<EOF

Installed under: $DEST
Next: run scripts/setup-default-apps.sh to assign file types.
EOF
