# =====================================================================
#  Packages
# =====================================================================

PKGS_CORE=(
	# X11 session
	i3-wm i3status i3lock xinit x11-xserver-utils x11-utils xserver-xorg
	xserver-xorg-input-libinput xserver-xorg-video-all xserver-xorg-video-fbdev
	xauth dbus-x11 xcape numlockx
	# bar (bundled GTK3 program), terminal, launcher, notifications,
	# wallpaper, idle
	python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 gir1.2-pango-1.0
	python3-xlib python3-i3ipc
	rofi dunst feh xwallpaper picom
	# desktop plumbing
	dbus dbus-user-session libpam-systemd polkitd lxpolkit brightnessctl playerctl
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
# there is no logind session, so /run/user/<uid> is never created and the
# session bus, pulseaudio and every XDG runtime consumer fall back to /tmp:
# the greeter accepts the password and the session comes up half broken.
# It is therefore listed explicitly.
#
# xserver-xorg-video-all is what actually gives X a usable driver (modesetting
# for KMS hardware); the bare `xserver-xorg` metapackage pulls the server but
# leaves the driver choice to whatever happens to be installed.

PKGS_APPS=(
	pcmanfm gvfs gvfs-backends btop fastfetch pavucontrol network-manager-gnome
	imv nomacs mpv flameshot swappy cliphist
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
	lxpolkit         # polkit authentication agent for the i3 session
	gvfs             # trash, network and mtp volumes
	gvfs-backends
	gvfs-fuse
)

PKGS_BAR_DEPS=(
	pavucontrol    # volume / microphone pill
	rofi           # launcher pill and every menu the helpers open
	network-manager-gnome  # nm-connection-editor, right-click on the network pill
	# The screenshot and colour dropper buttons are bar actions, so their
	# tools belong here and not in the optional apps: with --no-apps the
	# buttons must still work.
	maim           # full-screen and region capture
	slop           # region / single-pixel selection
	xclip          # clipboard for the screenshot and colour helpers
	xdotool        # window activation for the calendar / monitor popups
	xprintidle     # idle time for the lock helper
	xss-lock       # lock on suspend / screensaver
	xinput         # touchpad settings (tap, natural scroll, dwt)
	x11-xkb-utils  # setxkbmap, for Caps Lock -> Ctrl
	i3-wm          # i3-msg drives workspace switching and reloads
	jq             # the bar parses i3's tree to pick the tooltip / layout
	# The bar is a C program built at install time, so it needs headers rather
	# than a Python GTK stack; this replaces ~60 MB of runtime with a 47 KB
	# binary.
	build-essential pkg-config
	libcairo2-dev libpango1.0-dev libx11-dev
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
	# fcitx5 may already be installed from an earlier run: wire it into the
	# session even when no optional component is selected this time. Doing this
	# before the "any" short-circuit is what makes that possible.
	if command -v fcitx5 >/dev/null 2>&1 && [[ ${OPT_DRY_RUN} -eq 0 ]]; then
		write_fcitx_env
	fi

	local any=0
	[[ ${SOFT_FIREFOX:-0} -eq 1 || ${SOFT_ZENNB:-0} -eq 1 || ${SOFT_VLC:-0} -eq 1 || ${SOFT_OBS:-0} -eq 1 || ${SOFT_FCITX:-0} -eq 1 || ${SOFT_OSK:-0} -eq 1 ]] && any=1
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
	fi
	# Freshly installed here, so its session wiring has to be written now.
	if [[ ${SOFT_FCITX:-0} -eq 1 && ${OPT_DRY_RUN} -eq 0 ]]; then
		write_fcitx_env
	fi
	if [[ ${SOFT_FIREFOX:-0} -eq 1 ]]; then
		install_firefox || ui_warn "Firefox could not be installed"
	fi
	if [[ ${SOFT_ZENNB:-0} -eq 1 ]]; then
		install_zen_browser || ui_warn "Zen Browser could not be installed"
	fi
	if [[ ${SOFT_OSK:-0} -eq 1 ]]; then
		# Accessibility on-screen keyboard.
		#
		# wvkbd cannot be used here: it is Wayland-only, and this session is
		# X11. onboard is the smallest thing that actually works on X11, but
		# it is not free - 2 MB of itself plus 119 packages, because it pulls
		# in the GNOME accessibility stack. That is why it stays opt-in.
		# onboard-data carries the keyboard layouts and at-spi is what lets
		# onboard talk to the focused window. Both are Recommends, so
		# --no-install-recommends drops them, and without them onboard starts
		# and exits immediately with "Atspi typelib missing" - the package
		# alone is not enough.
		apt_install "onboard" onboard onboard-data \
			gir1.2-atspi-2.0 at-spi2-core \
			|| ui_warn "onboard could not be installed"
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

	# 2) Make fcitx5 start with the session. Without an autostart entry it
	#    only ran when something happened to launch it, so a fresh login had no
	#    input method until the user started it by hand. The XDG autostart file
	#    works for both i3 (X11) and sway (Wayland) because both sessions honour
	#    ~/.config/autostart via xdg-autostart.
	local adir="${HOME_DIR}/.config/autostart"
	mkdir -p "${adir}"
	cat >"${adir}/org.fcitx.Fcitx5.desktop" <<'FCAUTO'
[Desktop Entry]
Type=Application
Name=Fcitx 5
Comment=Start the input method with the session
Exec=fcitx5 -d --disable virtualkeyboard,emoji,table,spell,kimpanel,quickphrase,unicode,clipboard,notificationitem,fcitx4frontend,ibusfrontend,wayland,waylandim
Icon=fcitx
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
NoDisplay=true
FCAUTO
	register_file "${adir}/org.fcitx.Fcitx5.desktop"
	chown_user "${adir}" 2>/dev/null || true

	# 3) Export the IM modules so every toolkit picks fcitx up.
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

	# 4) Input method order: English first, Pinyin second. The file must be
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

	# 5) Ctrl+Space toggles between the two. Writing the section explicitly
	#    keeps it even when fcitx5 recreates config on first start.
	# A partial [Hotkey] block gets rewritten by fcitx5 on exit, which could
	# lose TriggerKeys; ship the full set. Ctrl+Space cycles the two input
	# methods enabled in `profile` (English / Pinyin).
	# Bindings live in conf/hotkey.conf.
	mkdir -p "${fdir}/conf"
	cat >"${fdir}/conf/hotkey.conf" <<'FCHOTKEY'
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=
ModifierOnlyKeyTimeout=250
[Hotkey/TriggerKeys]
1=Control+space
2=Zenkaku_Hankaku
3=Hangul
4=Hangul_Hanja
[Hotkey/AltTriggerKeys]
1=Shift_L
[Hotkey/ActivateKeys]
1=Super+space
[Hotkey/DeactivateKeys]
1=Super+space
[Hotkey/TogglePinyin]
1=Super+space
FCHOTKEY
	register_file "${fdir}/conf/hotkey.conf"


	cat >"${fdir}/config" <<'FCCONFIG'
[Hotkey]
TriggerKeys=Control+space
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=
ActivateKeys=
DeactivateKeys=
TogglePinyin=Super+space
TogglePinyinFirstCandidate=Shift
PrevPage=minus
NextPage=equal

[Behavior]
ActiveByDefault=False
ShareInputState=No
ShowInputMethodInformation=True
ShowInputMethodInformationWhenFocusIn=False
EnableAddonForAllPrograms=True
FCCONFIG

	# Trim the loaded addon set. fcitx5 loads every installed addon by default;
	# the heavy ones (virtual keyboard, emoji, table IMEs, spell checker) are
	# not needed for Chinese/English typing and cost real memory.
	#
	# Neither ~/.config/fcitx5/config [Addon/*] nor conf/addon.conf has any
	# effect on this build - it logged "Disabled Addons: {}" for both. The
	# supported switch is --disable, carried by the autostart entry.
	FCITX_DISABLE="virtualkeyboard,emoji,table,spell,kimpanel,quickphrase,unicode,clipboard,notificationitem,fcitx4frontend,ibusfrontend,wayland,waylandim"
	register_file "${fdir}/config"
	register_file "${fdir}/config"
	chown_user "${fdir}" 2>/dev/null || true

	# 5) X11 sessions started from a TTY (startx / xinit) do not source
	#    environment.d - only a systemd user session does - so mirror the same
	#    exports into ~/.xprofile, which is what the X session reads.
	local xp="${HOME_DIR}/.xprofile"
	local marker_begin="# >>> i3-everforest fcitx5 >>>"
	local marker_end="# <<< i3-everforest fcitx5 <<<"
	# Rewrite the block whenever its contents changed, not only when it is
	# missing. Wrapping it in fcitx5 is what caused the memory to creep back:
	# a stale "fcitx5 -d" (no --disable) started first, so i3's guarded launch
	# saw the process already running and skipped its --disable flags.
	local block
	block=$(printf '%s\n' \
		"${marker_begin}" \
		'export GTK_IM_MODULE=fcitx' \
		'export QT_IM_MODULE=fcitx' \
		'export XMODIFIERS=@im=fcitx' \
		"fcitx5 -d --disable ${FCITX_DISABLE} >/dev/null 2>&1 &" \
		"${marker_end}")

	local current=""
	if grep -qF "${marker_begin}" "${xp}" 2>/dev/null; then
		current=$(sed -n "/^${marker_begin}$/,/^${marker_end}$/p" "${xp}")
	fi
	if [[ "${current}" != "${block}" ]]; then
		[[ -f "${xp}" ]] && backup_path "${xp}"
		if grep -qF "${marker_begin}" "${xp}" 2>/dev/null; then
			# Replace just the marked block, leaving the rest untouched.
			local tmp
			tmp=$(mktemp)
			awk -v b="${marker_begin}" -v e="${marker_end}" -v repl="${block}" '
				$0 == b { print repl; skip = 1; next }
				$0 == e { skip = 0; next }
				!skip { print }
			' "${xp}" >"${tmp}"
			cat "${tmp}" >"${xp}"
			rm -f "${tmp}"
		else
			printf '%s\n' "${block}" >>"${xp}"
		fi
		register_file "${xp}"
		chown_user "${xp}" 2>/dev/null || true
	fi

	ui_ok "fcitx5 enabled (English + Pinyin, Ctrl+Space to switch)"
	return 0
}

# Zen Browser is installed with the project's own official installer. That
# script is the single source of truth for the layout (it unpacks the release
# under $HOME/.tarball-installations/zen), so it is fetched and executed
# verbatim instead of re-implementing its download/unpack logic here.
#
#   curl -fsSL https://updates.zen-browser.app/install.sh | bash
#
# The installer needs no root: it writes into the target user's home, so it is
# run as that user.
ZEN_INSTALL_URL="https://updates.zen-browser.app/install.sh"

# Mozilla's APT repository, so Firefox comes from Mozilla rather than from
# Debian's ESR build (which lags several major versions behind).
#
# The steps and the fingerprint are exactly what Mozilla documents for Debian
# and Ubuntu. Two details differ per release:
#   - Debian 13 (trixie) / Ubuntu 24.10+ need the deb822 ".sources" format;
#     older releases use the one-line "deb ..." form.
#   - the GPG key must be imported to /etc/apt/keyrings before either.
install_mozilla_repo() {
	local keyring="/etc/apt/keyrings/packages.mozilla.org.asc"
	local expected="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would configure the Mozilla APT repository"
		return 0
	fi

	# wget is the tool Mozilla's instructions use; make sure it exists.
	if ! command -v wget >/dev/null 2>&1; then
		apt_install "wget" wget || return 1
	fi
	install -d -m 0755 /etc/apt/keyrings

	if [[ ! -s "${keyring}" ]]; then
		ui_step "importing the Mozilla signing key"
		if ! wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg \
			-O- >"${keyring}.part" 2>>"${LOG_FILE}"; then
			ui_err "could not download the Mozilla signing key"
			rm -f "${keyring}.part"
			return 1
		fi
		mv "${keyring}.part" "${keyring}"
		chmod 644 "${keyring}"
	fi

	# Verify the fingerprint - an unexpected key must never be trusted, since
	# the repository is pinned above every other source below.
	if command -v gpg >/dev/null 2>&1; then
		local fp
		fp=$(gpg -n -q --import --import-options import-show "${keyring}" 2>/dev/null |
			awk '/pub/{getline; gsub(/^ +| +$/,""); print; exit}')
		if [[ "${fp}" != "${expected}" ]]; then
			ui_err "Mozilla key fingerprint mismatch (${fp:-none})"
			return 1
		fi
		ui_dim "Mozilla key fingerprint verified"
	fi

	# Pick the source format from the actual distribution.
	#
	#   Debian 13 "trixie" and newer  -> deb822 ".sources"
	#   Debian 12 "bookworm" and older-> one-line ".list"
	#   Ubuntu 24.10+                 -> deb822
	#   Ubuntu 24.04 and older        -> one-line
	#
	# Reading /etc/os-release in a subshell returns nothing, which is why the
	# distribution has to be sourced here rather than captured with $(...).
	local distro="" codename="" deb822=0
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		distro="${ID:-}"
		codename="${VERSION_CODENAME:-}"
		local ver="${VERSION_ID:-0}"
	fi

	case "${distro}" in
	debian)
		# trixie = 13, forky = 14; sid has no number and tracks the newest.
		case "${codename}" in
		trixie|forky|sid) deb822=1 ;;
		"")
			# No codename: fall back to the major version number.
			[[ ${ver%%.*} -ge 13 ]] 2>/dev/null && deb822=1
			;;
		esac
		;;
	ubuntu)
		# 24.10 "oracular" is the first release that expects deb822 here.
		local major="${ver%%.*}" minor="${ver#*.}"
		if [[ ${major} -gt 24 ]] 2>/dev/null; then
			deb822=1
		elif [[ ${major} -eq 24 ]] 2>/dev/null && [[ ${minor:-0} -ge 10 ]] 2>/dev/null; then
			deb822=1
		fi
		;;
	*)
		# Unknown derivative: prefer deb822 when apt is new enough to parse it.
		if apt-get --version 2>/dev/null | head -1 | grep -qE 'apt ([2-9]|[1-9][0-9])\.'; then
			deb822=1
		fi
		;;
	esac
	ui_dim "distribution: ${distro:-unknown} ${codename:-} -> $([[ ${deb822} -eq 1 ]] && echo deb822 || echo 'one-line')"

	if [[ ${deb822} -eq 1 ]]; then
		rm -f /etc/apt/sources.list.d/mozilla.list
		ui_step "writing the Mozilla source (deb822)"
		cat >/etc/apt/sources.list.d/mozilla.sources <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: ${keyring}
EOF
		chmod 644 /etc/apt/sources.list.d/mozilla.sources
	else
		rm -f /etc/apt/sources.list.d/mozilla.sources
		ui_step "writing the Mozilla source (one-line)"
		echo "deb [signed-by=${keyring}] https://packages.mozilla.org/apt mozilla main" \
			>/etc/apt/sources.list.d/mozilla.list
		chmod 644 /etc/apt/sources.list.d/mozilla.list
	fi

	# Pin Mozilla above every other origin, so "firefox" resolves to Mozilla's
	# build even when Debian also ships one.
	ui_step "pinning packages.mozilla.org at priority 1000"
	cat >/etc/apt/preferences.d/mozilla <<EOF
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
	chmod 644 /etc/apt/preferences.d/mozilla

	if ! apt-get update >>"${LOG_FILE}" 2>&1; then
		ui_warn "apt-get update reported an error after adding Mozilla's repo"
	fi
	ui_ok "Mozilla APT repository configured"
	return 0
}

# Firefox from Mozilla's repository, plus the Simplified Chinese language pack.
install_firefox() {
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would install Firefox"; return 0; fi

	install_mozilla_repo || { ui_warn "Firefox skipped: the Mozilla repository is unavailable"; return 1; }

	# firefox-l10n-* comes from the same repository, so it is installed in the
	# same transaction - that also keeps the locale version in lockstep with
	# the browser (a mismatched locale is silently ignored).
	ui_step "installing Firefox + zh-CN language pack"
	if apt_install "firefox" firefox firefox-l10n-zh-cn; then
		ui_ok "Firefox installed: $(dpkg-query -W -f='${Version}' firefox 2>/dev/null)"
		return 0
	fi
	ui_warn "the language pack is optional; retrying Firefox alone"
	apt_install "firefox" firefox || return 1
	return 0
}

install_zen_browser() {
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would run: curl -fsSL ${ZEN_INSTALL_URL} | bash"
		return 0
	fi

	ui_step "installing Zen Browser (official installer)"
	local script="${TMPWORK}/zen-install.sh"
	local log="${TMPWORK}/zen-install.log"

	# Fetch first so a network failure is reported as a download problem
	# instead of a half-executed shell pipeline.
	if ! curl -fsSL --max-time 60 --retry 2 \
		"${ZEN_INSTALL_URL}" -o "${script}" >"${log}" 2>&1; then
		ui_warn "could not download the Zen installer"
		ui_dim "install it manually: curl -fsSL ${ZEN_INSTALL_URL} | bash"
		return 1
	fi
	if [[ ! -s "${script}" ]]; then
		ui_warn "the Zen installer came back empty"
		return 1
	fi
	# A piped installer is only worth running when it is actually a shell
	# script; a captive portal or proxy error page is not.
	if ! head -1 "${script}" | grep -q '^#!.*sh'; then
		ui_warn "the Zen installer did not look like a shell script; refusing to run it"
		rm -f "${script}"
		return 1
	fi

	# Run it as the target user: it installs under $HOME and needs no root.
	local rc=0
	as_user bash "${script}" >>"${log}" 2>&1 || rc=$?
	if [[ ${rc} -ne 0 ]]; then
		ui_warn "the Zen installer failed (exit ${rc})"
		sed -n '1,12p' "${log}" 2>/dev/null | sed 's/^/      /' >&2 || true
		rm -f "${script}"
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
	# rofi turns each Action into its own row - which is why Zen showed up as a
	# menu instead of one icon. Dropping the Actions line leaves a single,
	# plain launcher; the same commands stay reachable from Zen's own menu.
	if grep -q '^Actions=' "${desk}" 2>/dev/null; then
		as_user sed -i '/^Actions=/d' "${desk}" 2>/dev/null ||
			sed -i '/^Actions=/d' "${desk}" 2>/dev/null || true
		# Remove the now-orphaned [Desktop Action ...] groups as well.
		as_user sed -i '/^\[Desktop Action /,/^$/d' "${desk}" 2>/dev/null ||
			sed -i '/^\[Desktop Action /,/^$/d' "${desk}" 2>/dev/null || true
	fi

	# The official installer drops the binary in ~/.local/bin; make sure that
	# directory is on PATH for every session type.
	local prof="${HOME_DIR}/.profile"
	if [[ -f "${prof}" ]] && ! grep -q '\$HOME/.local/bin' "${prof}" 2>/dev/null; then
		backup_path "${prof}"
		{
			printf '\n# Added by the i3 Everforest installer (Zen Browser lives here)\n'
			printf 'case ":$PATH:" in\n'
			printf '  *":$HOME/.local/bin:"*) ;;\n'
			printf '  *) PATH="$HOME/.local/bin:$PATH" ;;\n'
			printf 'esac\nexport PATH\n'
		} >>"${prof}"
		register_file "${prof}"
		chown_user "${prof}" 2>/dev/null || true
	fi

	if command -v update-desktop-database >/dev/null 2>&1; then
		as_user update-desktop-database "${HOME_DIR}/.local/share/applications" >/dev/null 2>&1 ||
			update-desktop-database "${HOME_DIR}/.local/share/applications" >/dev/null 2>&1 || true
	fi

	ui_ok "Zen Browser installed (one launcher entry, no sub-menu)"
	return 0
}
