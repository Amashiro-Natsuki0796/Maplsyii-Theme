# 85-payload.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Payload: embedded assets (icons, GTK theme, wallpaper)
# ---------------------------------------------------------------------
#  Everything the look depends on ships inside this file, so the
#  installer works on a machine with no network at all. The blobs live
#  after PAYLOAD_MARKER at the end of the script as base64 blocks:
#
#     @@asset icons.tar.xz.b64
#     <base64 ...>
#     @@end
#
#  `--extract-assets DIR` writes them out for inspection.
# =====================================================================
PAYLOAD_MARKER="__SWAY_EVERFOREST_PAYLOAD_BELOW__"

assets_unpack_from_self() {
	local dir="$1"
	mkdir -p "${dir}"
	# Skip the first line: the marker itself is matched exactly.
	awk -v out="${dir}" -v marker="${PAYLOAD_MARKER}" '
		BEGIN { inpay = 0; name = "" }
		inpay == 0 {
			line = $0
			sub(/^#[[:space:]]*/, "", line)
			if (line == marker) inpay = 1
			next
		}
		/^@@asset / { name = $2; file = out "/" name; next }
		/^@@end/    { if (name != "") close(file); name = ""; next }
		name != ""  { print $0 >> file }
	' "${SELF}"

	local f base
	for f in "${dir}"/*.b64; do
		[[ -e "${f}" ]] || continue
		base="${f%.b64}"
		if base64 -d "${f}" >"${base}" 2>/dev/null; then
			rm -f "${f}"
		else
			ui_warn "could not decode $(basename "${f}")"
			rm -f "${f}" "${base}"
		fi
	done

	# Expand the archives in place.
	if [[ -f "${dir}/icons.tar.xz" ]]; then
		mkdir -p "${dir}/icons"
		tar -xJf "${dir}/icons.tar.xz" -C "${dir}/icons" 2>/dev/null || ui_warn "icon payload is damaged"
	fi
	if [[ -f "${dir}/gtk-theme.tar.xz" ]]; then
		mkdir -p "${dir}/gtk-theme"
		tar -xJf "${dir}/gtk-theme.tar.xz" -C "${dir}/gtk-theme" 2>/dev/null || ui_warn "theme payload is damaged"
	fi
	if [[ -f "${dir}/fonts.tar.xz" ]]; then
		mkdir -p "${dir}/fonts"
		tar -xJf "${dir}/fonts.tar.xz" -C "${dir}/fonts" 2>/dev/null || ui_warn "the font payload is damaged"
	fi
	if [[ -f "${dir}/sddm-theme.tar.xz" ]]; then
		mkdir -p "${dir}/sddm"
		tar -xJf "${dir}/sddm-theme.tar.xz" -C "${dir}/sddm" 2>/dev/null || ui_warn "the SDDM theme payload is damaged"
	fi
	if [[ -f "${dir}/bar-wl.tar.xz" ]]; then
		mkdir -p "${dir}/bar-wl"
		tar -xJf "${dir}/bar-wl.tar.xz" -C "${dir}/bar-wl" 2>/dev/null || ui_warn "the C bar payload is damaged"
	fi
	if [[ -f "${dir}/wallpaper.jpg.xz" ]]; then
		xz -dc "${dir}/wallpaper.jpg.xz" >"${dir}/wallpaper.jpg" 2>/dev/null || ui_warn "wallpaper payload is damaged"
		rm -f "${dir}/wallpaper.jpg.xz"
	fi
	return 0
}

assets_prepare() {
	if [[ -n "${ASSET_DIR}" ]]; then return 0; fi
	if [[ -n "${SCRIPT_ASSET_DIR:-}" && -d "${SCRIPT_ASSET_DIR}" ]]; then
		ASSET_DIR="${SCRIPT_ASSET_DIR}"
		return 0
	fi
	local dir="${TMPWORK}/assets"
	ui_step "unpacking the bundled assets"
	assets_unpack_from_self "${dir}" || return 1
	ASSET_DIR="${dir}"
	local n=0
	if [[ -d "${dir}/icons/${ICON_NAME}" ]]; then n=$((n + 1)); fi
	if [[ -d "${dir}/gtk-theme/${THEME_NAME}" ]]; then n=$((n + 1)); fi
	if [[ -s "${dir}/wallpaper.jpg" ]]; then n=$((n + 1)); fi
	if [[ -d "${dir}/sddm/silent" ]]; then n=$((n + 1)); fi
	if [[ -d "${dir}/fonts" ]]; then n=$((n + 1)); fi
	((n > 0)) || { ui_warn "the embedded payload is empty"; return 1; }
	ui_ok "assets ready (${n}/5)"
	return 0
}

extract_assets() {
	local dir="${1:-./sway-everforest-assets}"
	mkdir -p "${dir}"
	TMPWORK="${TMPWORK:-${dir}}"
	LOG_FILE=""
	printf '  unpacking the embedded payload into %s\n' "${dir}"
	assets_unpack_from_self "${dir}"
	# the archives themselves are kept, so they can be inspected
	printf '  contents:\n'
	find "${dir}" -maxdepth 2 -mindepth 1 -printf '    %p\n' 2>/dev/null | sort | head -20
	printf '  done\n'
}

# ---------------------------------------------------------------------
