#!/usr/bin/env bash
set -euo pipefail

# Route Finder double-clicks to OpenInNvim.app / OpenInVisiData.app.
# Requires scripts/build-open-apps.sh to have run first.
#
# Registers both UTI and extension forms: UTIs cover cases where an app
# claims the content type, extensions cover types without a registered UTI
# (e.g., .parquet, .kt).
#
# PDF is intentionally left alone (macOS Preview.app stays the default).

command -v duti >/dev/null || {
	echo "ERROR: duti not installed (dot sync-nix-profile)"
	exit 1
}

readonly APPS_DIR="$HOME/Library/Application Support/open-routing"
for app in OpenInNvim OpenInCsvLens OpenInVisiData; do
	[[ -d "$APPS_DIR/$app.app" ]] || {
		echo "ERROR: $app.app missing under $APPS_DIR. Run scripts/build-open-apps.sh first."
		exit 1
	}
done

readonly NVIM_ID="com.riii111.openinnvim"
readonly CSV_ID="com.riii111.openincsvlens"
readonly VD_ID="com.riii111.openinvisidata"

assign_uti() {
	local bundle="$1" uti="$2"
	duti -s "$bundle" "$uti" all 2>/dev/null || echo "  skip UTI $uti (not registered on this system)"
}

assign_ext() {
	local bundle="$1" ext="$2"
	duti -s "$bundle" ".$ext" all
}

echo "Assigning text / config / code -> OpenInNvim"
for uti in \
	net.daringfireball.markdown \
	public.plain-text \
	public.text \
	public.source-code \
	public.script \
	public.shell-script \
	public.python-script \
	public.json \
	public.yaml \
	org.tomlunity.toml \
	public.rust-source \
	com.apple.property-list; do
	assign_uti "$NVIM_ID" "$uti"
done

for ext in md mdx txt json yaml yml toml sh bash zsh rs go kt kts py lua tf hcl sql conf ini env log xml graphql proto; do
	assign_ext "$NVIM_ID" "$ext"
done

# Images are intentionally left with Preview.app (snacks.image float inside a terminal
# wrapper ends up awkward; render-markdown / img-clip still handle images inside
# markdown buffers in nvim).

echo "Assigning csv / tsv -> OpenInCsvLens (delimiter auto-detected)"
for uti in public.comma-separated-values-text public.tab-separated-values-text; do
	assign_uti "$CSV_ID" "$uti"
done
for ext in csv tsv; do
	assign_ext "$CSV_ID" "$ext"
done

echo "Assigning parquet / sqlite / ndjson / jsonl -> OpenInVisiData (csvlens scope)"
# VisiData handles what csvlens can't: columnar, multi-table SQLite, row-per-line JSON.
for ext in parquet sqlite sqlite3 db ndjson jsonl; do
	assign_ext "$VD_ID" "$ext"
done

# xlsx is opt-in: overriding it hijacks Numbers / Excel for work spreadsheets.
# Uncomment to route .xlsx to VisiData as well.
# assign_uti "$VD_ID" org.openxmlformats.spreadsheetml.sheet
# assign_ext "$VD_ID" xlsx

# .pdf is intentionally not touched. Preview.app remains the default.

echo
echo "Done. Verify with: duti -x md   (should print OpenInNvim bundle info)"
