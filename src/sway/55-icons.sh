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

# Make sure the fallback themes are named in the icon theme's inheritance chain.
#
# GTK resolves an icon by walking the theme, then each theme in its `Inherits`
# list in order. The bundled set contains no per-application artwork, so any app
# it does not carry - which is most of them - has to come from a later entry.
# With only gnome,hicolor in that list a browser fell through to the stock
# placeholder even though the Numix drawings were installed on the same machine.
#
# Numix-Circle first, because it is the closest match to this theme's shape, then
# Numix, then the original tail. Duplicates are dropped so re-running the
# installer does not grow the line.
icons_ensure_inherits() {
	local dest="$1"
	local index="${dest}/index.theme"
	[[ -f "${index}" ]] || return 0

	# Which of the fallback themes are actually present? Naming an absent theme
	# is harmless but pointless, and it makes the file harder to read.
	local -a want=()
	local t
	for t in Numix-Circle Numix; do
		if [[ -d "/usr/share/icons/${t}" || -d "/usr/local/share/icons/${t}" ||
		      -d "${HOME_DIR}/.local/share/icons/${t}" ]]; then
			want+=("${t}")
		fi
	done

	local tail="gnome,hicolor"
	local cur
	cur="$(sed -n 's/^Inherits=//p' "${index}" 2>/dev/null | head -1)"
	[[ -n "${cur}" ]] && tail="${cur}"

	# Build the new list: our fallbacks first, then whatever was there.
	local -a all=("${want[@]}")
	local IFS=',' part
	for part in ${tail}; do
		[[ -n "${part}" ]] && all+=("${part}")
	done
	unset IFS

	local -a uniq=()
	local seen=" " p
	for p in "${all[@]}"; do
		case "${seen}" in
		*" ${p} "*) continue ;;
		esac
		seen="${seen}${p} "
		uniq+=("${p}")
	done

	[[ ${#uniq[@]} -eq 0 ]] && return 0

	local joined
	joined="$(printf '%s,' "${uniq[@]}")"
	joined="${joined%,}"

	# Already correct? Leave the file alone.
	[[ "${cur}" == "${joined}" ]] && return 0

	if grep -q '^Inherits=' "${index}" 2>/dev/null; then
		sed -i "s|^Inherits=.*|Inherits=${joined}|" "${index}"
	else
		printf 'Inherits=%s\n' "${joined}" >>"${index}"
	fi
	ui_dim "icon fallback chain: ${joined}"
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

	# The bundled set is deliberately small: it carries the Everforest folder
	# colours and the panel/status glyphs the bar uses, not one icon per
	# application. Its index.theme inherits from gnome,hicolor, and hicolor only
	# holds a handful of apps, so wofi showed generic placeholders for anything
	# that was not in the bundle.
	#
	# Numix is installed as a fallback for exactly this reason, but installing it
	# is not enough - it has to be named in the inheritance chain, or GTK never
	# looks there. Appending it means a missing icon resolves to the Numix
	# drawing instead of the default placeholder.
	icons_ensure_inherits "${dest}"

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
