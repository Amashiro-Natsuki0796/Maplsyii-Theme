# 40-packages.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Packages
# =====================================================================

PKGS_CORE=(
	sway foot wofi swaybg swayidle swaylock mako-notifier weston
	grim slurp wl-clipboard xwayland xdg-desktop-portal-wlr xdg-desktop-portal-gtk
	dbus dbus-x11 dbus-user-session libpam-systemd polkitd lxpolkit brightnessctl playerctl
	network-manager pipewire wireplumber pulseaudio-utils
	fonts-jetbrains-mono fonts-font-awesome fonts-dejavu-core fonts-noto-color-emoji
	adwaita-icon-theme libglib2.0-bin gsettings-desktop-schemas xdg-user-dirs
	gtk2-engines-murrine gnome-themes-extra librsvg2-common libgtk-3-bin
	xz-utils curl ca-certificates jq unzip tar sudo xdg-utils
	desktop-file-utils
	# bar actions: notify-send for the helpers, cal for the clock popup
	libnotify-bin bsdmainutils
)

# libpam-systemd is only a Recommends of sddm and of systemd-sysv, so
# `apt install --no-install-recommends` silently skips it. Without pam_systemd
# there is no logind session, /run/user/<uid> is never created, and sway
# cannot open its DRM device: the greeter accepts the password, the screen
# goes black and sway has already exited. It is therefore listed explicitly,
# and so is the seat manager used when logind is not in charge.

PKGS_APPS=(
	pcmanfm gvfs gvfs-backends btop fastfetch pavucontrol network-manager-gnome
	imv nomacs mpv wlogout swappy cliphist
	imagemagick
)

# Pills on the bar call these directly; without them a click silently does
# nothing, so they are core rather than optional apps.
# PCManFM delegates archive handling to an external program (it hard-codes
# "ark" rather than using any registered handler) and removable-media eject
# goes through udisks2 + a polkit agent. Without this trio the context menu
# entries exist but do nothing.
PKGS_FILEMANAGER_DEPS=(
	# libfm does not hard-code one archiver: /usr/share/libfm/archivers.list
	# defines file-roller, xarchiver, squeeze, engrampa and ark, and any of them
	# works. xarchiver is chosen because it is the lightest of the five
	# (~1.7 MB, 4 dependencies) and is a GTK app like the rest of the rice -
	# ark would pull in ~33 KDE libraries for the same result.
	xarchiver
	7zip             # 7z support behind xarchiver
	udisks2          # mount/eject removable media
	polkitd          # authorization for those mount operations
	lxpolkit         # polkit authentication agent for the sway session
	gvfs             # trash, network and mtp volumes
	gvfs-backends
	gvfs-fuse
)

PKGS_BAR_DEPS=(
	pavucontrol    # volume / microphone pill
	wlogout        # power pill
	wofi           # launcher pill (also in core, kept here for clarity)
	network-manager-gnome  # nm-connection-editor, right-click on the network pill
)

PKGS_ICONS_FALLBACK=(numix-icon-theme numix-icon-theme-circle)

apt_update_once() {
	if ((APT_UPDATED)); then return 0; fi
	ui_step "refreshing package lists (apt-get update)"
	if ! apt-get update -qq >>"${LOG_FILE}" 2>&1; then
		ui_warn "apt-get update reported an error - continuing with the existing lists"
	fi
	APT_UPDATED=1
}
APT_UPDATED=0

apt_install() {
	# apt_install <group-label> <pkg>...
	local label="$1"; shift
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		local -a missing=()
		local q
		for q in "$@"; do
			[[ -n "${q}" ]] || continue
			pkg_installed "${q}" || missing+=("${q}")
		done
		if [[ ${#missing[@]} -gt 0 ]]; then
			ui_dim "would install ${label}: ${missing[*]}"
		else
			ui_ok "${label}: already installed"
		fi
		return 0
	fi
	local -a want=() need=()
	local p
	for p in "$@"; do
		[[ -z "${p}" ]] && continue
		want+=("${p}")
		pkg_installed "$p" || need+=("${p}")
	done
	# Record every package this script is responsible for, including ones that
	# happened to be installed already: the uninstall step compares the list
	# against preinstalled-packages.txt and only removes what was genuinely
	# absent before. Skipping the recording here is why a re-run on a machine
	# that already had the packages left nothing to uninstall.
	local rec
	for rec in "${want[@]}"; do manifest_pkg "$(apt_cleanup_name "${rec}")"; done

	if [[ ${#need[@]} -eq 0 ]]; then
		ui_ok "${label}: already installed (${#want[@]} packages)"
		return 0
	fi
	ui_step "${label}: installing ${#need[@]} package(s)"
	ui_dim "  ${need[*]}"
	apt_update_once
	if ! apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confdef \
		-o Dpkg::Options::=--force-confold "${need[@]}" >>"${LOG_FILE}" 2>&1; then
		ui_err "apt could not install: ${need[*]}"
		ui_dim "  see ${LOG_FILE}"
		return 1
	fi
	ui_ok "${label}: done"
}

install_packages() {
	ui_hdr "Packages"
	if [[ ${CORE} -eq 1 ]]; then
		apt_install "core" "${PKGS_CORE[@]}" || die "the core package set is required; aborting"
	fi
	if [[ ${APPS} -eq 1 ]]; then
		# The file manager's extract and eject menu entries need these.
		apt_install "file manager" "${PKGS_FILEMANAGER_DEPS[@]}" || \
			ui_warn "archive and removable-media actions may not work"
		# libfm picks the first entry in archivers.list that is installed, so a
		# pre-existing file-roller/engrampa is fine too. Only warn when nothing
		# can handle an archive at all.
		local archiver_ok=0 a
		for a in file-roller xarchiver engrampa ark squeeze; do
			if command -v "${a}" >/dev/null 2>&1; then archiver_ok=1; break; fi
		done
		if [[ ${archiver_ok} -eq 0 ]]; then
			ui_warn "no archive manager found - extracting from the file manager will not work"
		fi
	fi
	if [[ ${DOTS} -eq 1 ]]; then
		# The bar's pills call these; without them a click does nothing.
		apt_install "bar actions" "${PKGS_BAR_DEPS[@]}" || \
			ui_warn "some bar actions will not work (their programs are missing)"
	fi
	if [[ ${APPS} -eq 1 ]]; then
		apt_install "apps" "${PKGS_APPS[@]}" || ui_warn "some optional apps failed to install (the rice still works)"
	fi
	if [[ ${ICONS} -eq 1 && ${ICON_EMBEDDED:-0} -eq 0 ]]; then
		apt_install "icon fallback" "${PKGS_ICONS_FALLBACK[@]}" || true
	fi
	if [[ ${GTK_THEME} -eq 1 ]]; then
		apt_install "gtk theme deps" gtk2-engines-murrine gnome-themes-extra librsvg2-common libgtk-3-bin || true
	fi
}

# ---------------------------------------------------------------------
#  Optional software (third page of the TUI)
# ---------------------------------------------------------------------
install_optional_software() {
	local any=0
	[[ ${SOFT_ZENNB:-0} -eq 1 || ${SOFT_VLC:-0} -eq 1 || ${SOFT_OBS:-0} -eq 1 || ${SOFT_FCITX:-0} -eq 1 ]] && any=1
	[[ ${any} -eq 1 ]] || return 0

	ui_hdr "Optional software"

	if [[ ${SOFT_VLC:-0} -eq 1 ]]; then
		apt_install "vlc" vlc || ui_warn "VLC could not be installed"
	fi
	if [[ ${SOFT_OBS:-0} -eq 1 ]]; then
		apt_install "obs-studio" obs-studio || ui_warn "OBS could not be installed"
	fi
	if [[ ${SOFT_FCITX:-0} -eq 1 ]]; then
		# Chinese pinyin plus the input-method modules GTK and Qt need.
		apt_install "fcitx5" fcitx5 fcitx5-chinese-addons \
			fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
			fcitx5-frontend-qt6 fcitx5-config-qt \
			|| ui_warn "fcitx5 could not be installed"
		if [[ ${OPT_DRY_RUN} -eq 0 ]]; then
			write_fcitx_env
		fi
	fi
	if [[ ${SOFT_ZENNB:-0} -eq 1 ]]; then
		install_zen_browser || ui_warn "Zen Browser could not be installed"
	fi
	return 0
}

# GTK/Qt applications only pick fcitx5 up when the IM module is exported.
write_fcitx_env() {
	local dir="${HOME_DIR}/.config/environment.d"
	local fdir="${HOME_DIR}/.config/fcitx5"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would configure fcitx5 (im-config, layout order, Ctrl+Space)"
		return 0
	fi

	# 1) Tell the session to use fcitx5. im-config writes ~/.xinputrc, which is
	#    what GTK/Qt and the X11 bridge read on login.
	if command -v im-config >/dev/null 2>&1; then
		as_user im-config -n fcitx5 >/dev/null 2>&1 ||
			ui_warn "im-config could not be set to fcitx5"
	fi

	# 2) Export the IM modules so every toolkit picks fcitx up.
	mkdir -p "${dir}"
	cat >"${dir}/fcitx5.conf" <<'ENVFILE'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
ENVFILE
	register_file "${dir}/fcitx5.conf"
	chown_user "${dir}" 2>/dev/null || true

	# 3) Input method order: English first, Pinyin second. The file must be
	#    self-contained - fcitx5 appends its own [Groups] block on first run, and
	#    a duplicate section means the older one wins.
	mkdir -p "${fdir}"
	cat >"${fdir}/profile" <<'FCPROFILE'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
FCPROFILE
	register_file "${fdir}/profile"
	chown_user "${fdir}" 2>/dev/null || true

	# 4) Ctrl+Space is bound in the sway config, NOT here.
	#
	# fcitx5's TriggerKeys only works on X11, where the client can grab the
	# keyboard globally. Under Wayland no client sees keys it does not own, so
	# a TriggerKeys entry here would be dead weight - and worse, on the X11
	# bridge it would race the compositor binding for the same combination.
	# Keeping the key list empty leaves sway as the single owner.
	cat >"${fdir}/config" <<'FCCONFIG'
[Hotkey]
TriggerKeys=
EnumerateWithTriggerKeys=True
FCCONFIG
	register_file "${fdir}/config"
	chown_user "${fdir}" 2>/dev/null || true

	# fcitx5 keeps the key bindings in a *second* file, conf/hotkey.conf, and
	# reads that one at runtime. Clearing TriggerKeys only in config left the
	# conflict in place, so both have to agree: empty here too, or fcitx5 grabs
	# Ctrl+Space again and the compositor binding never fires.
	mkdir -p "${fdir}/conf"
	cat >"${fdir}/conf/hotkey.conf" <<'FCHOTKEY'
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=

# Ctrl+Space is handled by the compositor (see the sway config), because a
# Wayland client cannot grab keys globally. Leaving this list empty keeps
# fcitx5 from competing for the same combination.
[Hotkey/TriggerKeys]
FCHOTKEY
	register_file "${fdir}/conf/hotkey.conf"
	chown_user "${fdir}" 2>/dev/null || true

	ui_ok "fcitx5 enabled (English + Pinyin, Ctrl+Space via sway)"
	return 0
}

# Zen Browser ships as a tarball on GitHub. There is no apt package, and the
# RPM/Flatpak routes are not what the user asked for, so fetch the release,
# unpack it under /opt and add a desktop entry.
install_zen_browser() {
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would run the official Zen installer"
		return 0
	fi

	ui_step "installing Zen Browser (official installer)"
	local script="${TMPWORK}/zen-install.sh"

	# Zen publishes its own installer; using it means the layout stays whatever
	# upstream decides instead of us guessing at paths.
	if ! curl -fsSL --max-time 60 --retry 2 \
		https://updates.zen-browser.app/install.sh -o "${script}" 2>/dev/null; then
		ui_warn "could not download the Zen installer"
		ui_dim "install it manually: curl -fsSL https://updates.zen-browser.app/install.sh | bash"
		return 1
	fi
	if [[ ! -s "${script}" ]]; then
		ui_warn "the Zen installer came back empty"
		return 1
	fi

	# Run it as the target user: it installs under $HOME and needs no root.
	if ! as_user bash "${script}" >"${TMPWORK}/zen-install.log" 2>&1; then
		ui_warn "the Zen installer failed"
		sed -n '1,8p' "${TMPWORK}/zen-install.log" 2>/dev/null | sed 's/^/      /' >&2 || true
		return 1
	fi
	rm -f "${script}"

	local desk="${HOME_DIR}/.local/share/applications/zen.desktop"
	if [[ ! -f "${desk}" ]]; then
		ui_warn "Zen installed but no desktop entry was created"
		return 1
	fi
	register_file "${desk}"

	# The upstream entry advertises desktop Actions, and a launcher such as
	# wofi turns each Action into its own row - which is why Zen showed up as a
	# menu instead of one icon. Dropping the Actions line leaves a single,
	# plain launcher; the same commands stay reachable from Zen's own menu.
	if grep -q '^Actions=' "${desk}" 2>/dev/null; then
		as_user sed -i '/^Actions=/d' "${desk}" 2>/dev/null ||
			sed -i '/^Actions=/d' "${desk}" 2>/dev/null || true
		# Remove the now-orphaned [Desktop Action ...] groups as well.
		as_user sed -i '/^\[Desktop Action /,/^$/d' "${desk}" 2>/dev/null ||
			sed -i '/^\[Desktop Action /,/^$/d' "${desk}" 2>/dev/null || true
	fi

	if command -v update-desktop-database >/dev/null 2>&1; then
		as_user update-desktop-database "${HOME_DIR}/.local/share/applications" >/dev/null 2>&1 ||
			update-desktop-database "${HOME_DIR}/.local/share/applications" >/dev/null 2>&1 || true
	fi

	ui_ok "Zen Browser installed (one launcher entry, no sub-menu)"
	return 0
}

# ---------------------------------------------------------------------
