#!/usr/bin/env bash
set -euo pipefail

# Route Finder double-clicks to OpenInNvim.app / OpenInCsvLens.app.
# Requires scripts/build-open-apps.sh to have run first.
#
# Registers known UTIs and the document types declared by OpenIn*.app.
#
# PDF is intentionally left alone (macOS Preview.app stays the default).

command -v duti >/dev/null || {
	echo "ERROR: duti not found. Run this script with: nix shell nixpkgs#duti --command bash scripts/setup-default-apps.sh"
	exit 1
}

readonly APPS_DIR="$HOME/Library/Application Support/open-routing"
for app in OpenInNvim OpenInCsvLens; do
	[[ -d "$APPS_DIR/$app.app" ]] || {
		echo "ERROR: $app.app missing under $APPS_DIR. Run scripts/build-open-apps.sh first."
		exit 1
	}
done

readonly NVIM_ID="com.riii111.openinnvim"
readonly CSV_ID="com.riii111.openincsvlens"

assign_uti() {
	local bundle="$1" uti="$2"
	duti -s "$bundle" "$uti" all 2>/dev/null || echo "  skip UTI $uti (not registered on this system)"
}

echo "Assigning text / config / code -> OpenInNvim"
for uti in \
	net.daringfireball.markdown \
	public.plain-text \
	public.text \
	public.source-code \
	public.script \
	public.shell-script \
	public.bash-script \
	public.zsh-script \
	public.python-script \
	public.json \
	public.yaml \
	org.tomlunity.toml \
	public.rust-source \
	public.xml \
	com.apple.log \
	com.apple.property-list; do
	assign_uti "$NVIM_ID" "$uti"
done
duti -s "$NVIM_ID" "$NVIM_ID.document" all

# Images are intentionally left with Preview.app (snacks.image float inside a terminal
# wrapper ends up awkward; render-markdown / img-clip still handle images inside
# markdown buffers in nvim).

echo "Assigning csv / tsv -> OpenInCsvLens (delimiter auto-detected)"
for uti in public.comma-separated-values-text public.tab-separated-values-text; do
	assign_uti "$CSV_ID" "$uti"
done
duti -s "$CSV_ID" "$CSV_ID.document" all

# .pdf is intentionally not touched. Preview.app remains the default.

echo
echo "macOS may ask you to confirm changes to existing file associations."
echo "Done. Verify with: nix shell nixpkgs#duti --command duti -x md   (should print OpenInNvim bundle info)"
