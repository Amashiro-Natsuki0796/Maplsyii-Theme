# =====================================================================
#  Wallpaper
# =====================================================================
WALL_DIR_NAME="${SHARE_DIR_NAME}"

wallpaper_path() { printf '%s/.local/share/%s/wallpaper.jpg' "${HOME_DIR}" "${WALL_DIR_NAME}"; }

wallpaper_install() {
	ui_hdr "Wallpaper"
	local dest_dir="${HOME_DIR}/.local/share/${WALL_DIR_NAME}"
	local dest="${dest_dir}/wallpaper.jpg"

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would install ${dest}"; return 0; fi
	mkdir -p "${dest_dir}"

	if [[ -f "${ASSET_DIR}/wallpaper.jpg" ]]; then
		ui_step "copying the bundled wallpaper"
		cp -a "${ASSET_DIR}/wallpaper.jpg" "${dest}"
	elif curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 \
		-o "${dest}.part" "${WALLPAPER_URL}" >>"${LOG_FILE}" 2>&1; then
		mv "${dest}.part" "${dest}"
		ui_step "wallpaper downloaded from wallhaven"
	else
		ui_warn "could not fetch the wallpaper; generating an Everforest gradient instead"
		wallpaper_generate "${dest}"
	fi

	# A 1920x1080 JPEG should be at least a few dozen KB.
	if [[ ! -s "${dest}" ]] || [[ "$(stat -c%s "${dest}")" -lt 20000 ]]; then
		wallpaper_generate "${dest}"
	fi

	chown_user "${dest_dir}"
	register_file "${dest}"
	ui_ok "wallpaper: ${dest}"

	# Lock screen background + lightdm greeter (best effort)
	mkdir -p /usr/share/backgrounds
	ln -sfn "${dest}" /usr/share/backgrounds/i3-everforest.jpg
	manifest_file /usr/share/backgrounds/i3-everforest.jpg
}

wallpaper_generate() {
	local dest="$1"
	ui_step "generating a fallback wallpaper"
	if have convert; then
		convert -size 1920x1080 gradient:'#1e2326-#4b5a43' "${dest}" >>"${LOG_FILE}" 2>&1 && return 0
	fi
	# last resort: a 1x1 solid JPEG in the Everforest background colour
	if have convert; then
		convert -size 1920x1080 xc:'#1e2326' "${dest}" >>"${LOG_FILE}" 2>&1 && return 0
	fi
	return 1
}

# =====================================================================
#  Icon font (Nerd Font symbols)
# ---------------------------------------------------------------------
#  The bar and the prompt use Nerd Font glyphs (volume, brightness,
#  colour picker, terminal, notification bell, ...). Debian has no Nerd
#  Font package, and fonts-font-awesome is only 4.7, so the symbols are
#  bundled and installed into the user's font directory.
# =====================================================================
fonts_install() {
	ui_hdr "Icon font"
	local src="${ASSET_DIR}/fonts"
	local dest="${HOME_DIR}/.local/share/fonts"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would install the Nerd Font symbols into ${dest}"
		return 0
	fi

	if [[ ! -d "${src}" ]]; then
		ui_warn "the bundled font payload is missing; bar icons may show as boxes"
		return 1
	fi

	mkdir -p "${dest}"
	local f n=0
	for f in "${src}"/*.ttf; do
		[[ -f "${f}" ]] || continue
		if have cmp && cmp -s "${f}" "${dest}/$(basename "${f}")" 2>/dev/null; then
			continue
		fi
		cp -f "${f}" "${dest}/$(basename "${f}")" || continue
		register_file "${dest}/$(basename "${f}")"
		n=$((n + 1))
	done
	chown_user "${dest}"

	if have fc-cache; then
		as_user fc-cache -f "${dest}" >/dev/null 2>&1 || true
	fi

	if ((n > 0)); then
		ui_ok "installed ${n} font file(s) into ${dest}"
	else
		ui_ok "icon font already present"
	fi
	return 0
}
