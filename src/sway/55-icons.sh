# 55-icons.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Icon theme  (Material-Black-Lime-Numix-FLAT)
# ---------------------------------------------------------------------
#  1. bundled payload (exact icon set from the screenshot)
#  2. Numix from the Debian archive, recoloured to lime (offline build)
# =====================================================================

icons_install_bundled() {
	local dest="/usr/share/icons/${ICON_NAME}"

	# assets_prepare() already expanded the archives, so prefer the
	# unpacked tree; fall back to the archive for the development layout.
	if [[ -d "${ASSET_DIR}/icons/${ICON_NAME}" ]]; then
		ui_step "installing the bundled icon theme"
		mkdir -p /usr/share/icons
		rm -rf "${dest}"
		cp -a "${ASSET_DIR}/icons/${ICON_NAME}" "${dest}" || return 1
	elif [[ -f "${ASSET_DIR}/icons.tar.xz" ]]; then
		ui_step "extracting the bundled icon theme"
		mkdir -p /usr/share/icons
		rm -rf "${dest}"
		tar -xJf "${ASSET_DIR}/icons.tar.xz" -C /usr/share/icons 2>/dev/null || return 1
	fi

	[[ -d "${dest}" ]] || return 1
	ui_ok "icons installed from the bundled payload"
	return 0
}

icons_build_from_numix() {
	have gtk-update-icon-cache >/dev/null 2>&1 || true
	# make sure Numix exists
	if ! pkg_installed numix-icon-theme; then
		apt_install "numix icons" "${PKGS_ICONS_FALLBACK[@]}" || return 1
	fi

	local src="" cand
	for cand in /usr/share/icons/Numix /usr/share/icons/Numix-Circle; do
		if [[ -d "${cand}" ]]; then src="${cand}"; break; fi
	done
	[[ -n "${src}" ]] || return 1

	local dest="/usr/share/icons/${ICON_NAME}"
	ui_step "generating ${ICON_NAME} from Numix (lime folders, black glyphs)"
	rm -rf "${dest}"
	cp -a "${src}" "${dest}"

	# Recolour the folders: Numix orange -> Everforest lime.
	local f
	while IFS= read -r -d '' f; do
		sed -i \
			-e 's/#ea9036/#b9ff66/Ig' \
			-e 's/#f2bb64/#cdfa8f/Ig' \
			-e 's/#f6c37d/#d7fba4/Ig' \
			-e 's/#e58b32/#a8ef55/Ig' \
			"${f}" 2>/dev/null || true
	done < <(find "${dest}" -name '*.svg' -print0 2>/dev/null)

	# Darken the application glyphs a little so they read as "black".
	while IFS= read -r -d '' f; do
		sed -i -e 's/#ffffff/#1e2326/Ig' -e 's/#f9f9f9/#1e2326/Ig' "${f}" 2>/dev/null || true
	done < <(find "${dest}/48/apps" "${dest}/64/apps" -name '*.svg' -print0 2>/dev/null)

	# Rewrite the identity
	cat >"${dest}/index.theme" <<EOF
[Icon Theme]
Name=${ICON_NAME}
Comment=Numix icons recoloured with the Everforest lime palette
Inherits=gnome,hicolor
Example=folder
Directories=$(find "${dest}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -u | paste -sd, -)

EOF
	find "${dest}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -u | while read -r d; do
		{
			printf '[%s]\nSize=%s\nContext=%s\nType=Fixed\n\n' \
				"${d}" "${d%%@*}" \
				"$(case "${d}" in
					*/actions) echo Actions ;;
					*/apps) echo Applications ;;
					*/devices) echo Devices ;;
					*/places) echo Places ;;
					*/status) echo Status ;;
					*/categories) echo Categories ;;
					*/mimetypes) echo MimeTypes ;;
					*/emblems) echo Emblems ;;
					*/panel) echo Panel ;;
					*/notifications) echo Notifications ;;
					*) echo Applications ;;
					esac)"
		} >>"${dest}/index.theme"
	done
	ui_ok "generated ${dest}"
	return 0
}

icons_install() {
	ui_hdr "Icon theme"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would install ${ICON_NAME}"; return 0; fi

	local dest="/usr/share/icons/${ICON_NAME}"
	local stamp="${dest}/.sway-everforest-source"

	# The Numix fallback build uses the same theme name as the real icon
	# set, so the name alone cannot tell them apart: record where the
	# installed copy came from. The bundled payload always wins, because
	# it is the exact set from the screenshot.
	local current=""
	if [[ -f "${stamp}" ]]; then current="$(cat "${stamp}" 2>/dev/null)"; fi

	if [[ "${current}" == "payload" && -d "${dest}" ]]; then
		ui_ok "${ICON_NAME} is already installed (bundled set)"
	else
		if [[ -e "${dest}" ]]; then
			backup_path "${dest}"
			rm -rf "${dest}"
		fi
		if icons_install_bundled; then
			printf 'payload\n' >"${dest}/.sway-everforest-source"
			manifest_dir "${dest}"
		elif icons_build_from_numix; then
			printf 'numix-fallback\n' >"${dest}/.sway-everforest-source"
			manifest_dir "${dest}"
		else
			ui_warn "could not install the icon theme; keeping the current icons"
			return 1
		fi
	fi

	# Refresh the caches if the tools are available.
	if have gtk-update-icon-cache; then
		gtk-update-icon-cache -q -t -f "${dest}" 2>/dev/null || true
	fi
	ui_ok "icon theme ready: ${ICON_NAME}"
	return 0
}

# ---------------------------------------------------------------------
#  Icon overrides
# ---------------------------------------------------------------------
#  The reference screenshot shows an amber disc for the home folder and a red
#  bin, while the bundled set draws both in lime/steel. Those two glyphs are
#  replaced inside the installed theme.
#
#  Overlay themes (a user-level theme that Inherits the bundled one) were tried
#  first and rejected: GTK resolves the inherited icon fine, but the sidebar of
#  Nemo/PCManFM picks icons through the theme's own directory list, so a
#  two-directory overlay makes the whole set fall back to Adwaita and the
#  folders turn blue. Overwriting the installed theme keeps every index entry
#  valid and changes exactly the two files we ship.
icons_install_overrides() {
	local src="${ASSET_DIR}/icons/rice-overrides"
	local dest="/usr/share/icons/${ICON_NAME}"

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would install icon overrides into ${dest}"
		return 0
	fi
	if [[ ! -d "${src}" ]] || [[ ! -d "${dest}" ]]; then
		ui_dim "no icon overrides to install"
		return 0
	fi

	local f base n=0
	for f in "${src}"/*.svg; do
		[[ -f "${f}" ]] || continue
		base="$(basename "${f}")"
		# Write into every pixel size the theme ships, so a request at 24px
		# finds the same artwork as one at 48px.
		for d in "${dest}"/*/places; do
			[[ -d "${d}" ]] || continue
			[[ -f "${d}/${base}" ]] || continue
			cp -f "${f}" "${d}/${base}"
			register_file "${d}/${base}"
			n=$((n + 1))
		done
	done
	# The "-symbolic" names are what a file-manager sidebar asks for. They only
	# exist in scalable/, so they are written there explicitly.
	local sd="${dest}/scalable/places"
	if [[ -d "${sd}" ]]; then
		for f in "${src}"/*-symbolic.svg; do
			[[ -f "${f}" ]] || continue
			cp -f "${f}" "${sd}/$(basename "${f}")"
			register_file "${sd}/$(basename "${f}")"
			n=$((n + 1))
		done
	fi
	# Refresh the icon cache so file managers pick the new artwork up.
	if command -v gtk-update-icon-cache >/dev/null 2>&1; then
		gtk-update-icon-cache -f -t "${dest}" >/dev/null 2>&1 || true
	fi
	ui_ok "accent icons installed (${n} file(s) in ${ICON_NAME})"
	return 0
}

# ---------------------------------------------------------------------
