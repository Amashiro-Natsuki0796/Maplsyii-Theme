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
#  swayfx: the blur fork of sway
# ---------------------------------------------------------------------
#  The rice's configuration is written for swayfx, not for stock sway: blur,
#  blur_xray, blur_radius, layer_effects and `for_window ... blur on` are all
#  swayfx extensions. Stock sway does not know them, and its response is a red
#  swaynag banner reading "Unknown command" on every start - which is exactly
#  what a fresh Debian install produced before this function existed.
#
#  Debian has no swayfx package, so it is built from source here. The build is
#  the reason PKGS_SWAYFX_BUILD exists: meson, ninja, a compiler and the
#  wlroots/scenefx headers.
#
#  Version pinning matters. swayfx tracks a specific wlroots, and the system
#  wlroots in trixie is too old for it, so the sid wlroots is pulled in through
#  a pinned apt source - see the note in install_packages().
SWAYFX_VERSION="${SWAYFX_VERSION:-0.6}"
SWAYFX_URL="https://codeload.github.com/WillPower3309/swayfx/tar.gz/refs/tags/${SWAYFX_VERSION}"

# ---------------------------------------------------------------------
#  sid apt source for the wlroots/scenefx that swayfx needs
# ---------------------------------------------------------------------
#  swayfx 0.6 targets wlroots 0.20 and scenefx 0.5. Debian 13 (trixie) ships
#  wlroots 0.18 and no scenefx at all, so the build cannot be satisfied from the
#  stable suite. The two development packages are pulled from sid, and nothing
#  else is: a blanket sid source would let an unrelated `apt upgrade` drag the
#  whole system off stable.
#
#  A pin file keeps that promise. Packages matching libwlroots-0.20* and
#  scenefx* prefer sid (990), everything else prefers trixie (900) and sid sits
#  at 100 - the standard "sid is available but almost never chosen" setup.
SID_SOURCE="/etc/apt/sources.list.d/everforest-sid.list"
SID_PIN="/etc/apt/preferences.d/everforest-sid.pin"

# Set to 1 once the source is wanted; cleanup() removes it again if the build
# never finished. Declared here so `set -u` is happy when they are read.
SID_SOURCE_ADDED="${SID_SOURCE_ADDED:-0}"
SWAYFX_INSTALLED="${SWAYFX_INSTALLED:-0}"

sid_source_ensure() {
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would add a pinned sid source for the wlroots/scenefx headers"
		return 0
	fi

	# Already satisfiable? Then the source is not needed at all.
	if pkg-config --exists wlroots-0.20 scenefx-0.5 2>/dev/null; then
		return 0
	fi

	ui_step "adding a pinned sid source for the swayfx build headers"

	if [[ ! -f "${SID_SOURCE}" ]]; then
		# https, not http: the mirrors time out over plain http on some
		# networks and apt then hangs rather than failing fast.
		cat >"${SID_SOURCE}" <<'EOF'
# Added by the Sway Everforest installer.
#
# Only the wlroots 0.20 and scenefx 0.5 development packages are taken from
# sid; the pin file below makes sure nothing else is. Delete this file and the
# pin to return to a pure trixie system.
deb https://deb.debian.org/debian sid main
EOF
		register_file "${SID_SOURCE}"
		# Only a file this run created may be removed by cleanup(). A source the
		# user already had must survive a failed install.
		SID_SOURCE_ADDED=1
	fi

	if [[ ! -f "${SID_PIN}" ]]; then
		cat >"${SID_PIN}" <<'EOF'
# Added by the Sway Everforest installer.
#
# trixie wins by default (900), sid is available but almost never selected
# (100), and only the two packages swayfx needs prefer sid (990).
Package: *
Pin: release a=stable
Pin-Priority: 900

Package: *
Pin: release a=unstable
Pin-Priority: 100

Package: libwlroots-0.20* scenefx* libscenefx*
Pin: release a=unstable
Pin-Priority: 990
EOF
		register_file "${SID_PIN}"
	fi

	# Force a refresh even if apt-get update already ran earlier in this
	# install.
	#
	# APT_UPDATED exists so the package steps do not refresh the lists over and
	# over, but the earlier refresh happened before this source file existed -
	# so the sid index was never fetched and the two -dev packages below were
	# "unable to locate". Clearing the flag is what makes the next call actually
	# run apt-get update again.
	APT_UPDATED=0
	apt_update_once

	# Prove the packages are reachable before the build tries to install them.
	# Without this the failure surfaced much later as a wall of "Unable to
	# locate package" lines from apt, which reads like a broken installer
	# rather than "the sid mirror could not be reached".
	if ! apt-cache show libwlroots-0.20-dev >/dev/null 2>&1; then
		ui_err "libwlroots-0.20-dev is still not visible after adding the sid source"
		ui_dim "  the source is ${SID_SOURCE}; check that the sid mirror is reachable"
		return 1
	fi
	if ! apt-cache show libscenefx-0.5-dev >/dev/null 2>&1; then
		ui_err "libscenefx-0.5-dev is still not visible after adding the sid source"
		ui_dim "  the source is ${SID_SOURCE}; check that the sid mirror is reachable"
		return 1
	fi

	return 0
}

# Install the swayfx build dependencies without recording them for uninstall.
#
# These are needed for the compile and nothing else: meson, ninja, a compiler
# and a pile of -dev headers. Recording them in the manifest would make
# --uninstall try to remove them much later, when they have already been
# dropped on purpose. They are therefore installed here, outside apt_install(),
# and removed again as soon as the build finishes.
swayfx_build_deps_install() {
	local -a deps=(
		meson ninja-build gcc pkg-config curl xz-utils
		libwlroots-0.20-dev libscenefx-0.5-dev
		libwayland-dev wayland-protocols
		libpcre2-dev libjson-c-dev libevdev-dev libinput-dev
		libxkbcommon-dev libcairo2-dev libpango1.0-dev
		libgdk-pixbuf-2.0-dev libpam0g-dev libcap-dev
		libsystemd-dev libdisplay-info-dev libliftoff-dev
		libdrm-dev libgbm-dev libegl-dev libgles-dev
	)

	# Only what is actually missing, so a machine that already has a compiler
	# does not get it removed afterwards.
	local -a need=() p
	for p in "${deps[@]}"; do
		pkg_installed "${p}" || need+=("${p}")
	done

	if [[ ${#need[@]} -eq 0 ]]; then
		SWAYFX_DEPS_ADDED=()
		return 0
	fi

	ui_dim "  installing ${#need[@]} build package(s)"
	apt_update_once
	if ! apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confdef \
		-o Dpkg::Options::=--force-confold "${need[@]}" >>"${LOG_FILE}" 2>&1; then
		ui_err "the swayfx build dependencies could not be installed"
		return 1
	fi

	# Remember exactly what this run added, so the cleanup removes only that.
	SWAYFX_DEPS_ADDED=("${need[@]}")
	return 0
}

# Remove the build-only packages again.
#
# apt-get remove, not purge: the configuration files of a -dev package are
# tiny and purging risks taking a runtime library another program still wants.
# The removal is best-effort - a package that something else now depends on is
# simply kept, which is what apt decides on its own.
swayfx_build_deps_remove() {
	[[ ${#SWAYFX_DEPS_ADDED[@]} -eq 0 ]] && return 0

	# The two runtime libraries stay. libwlroots-0.20 and libscenefx-0.5 are
	# linked by the swayfx binary itself:
	#
	#   libscenefx-0.5.so => /usr/lib/x86_64-linux-gnu/libscenefx-0.5.so
	#
	# apt marks them automatic because only a -dev package depends on them, so
	# `apt-get remove --autoremove` on the -dev packages takes the runtime
	# libraries with it. sway then fails to resolve its own shared objects,
	# exits immediately, and SDDM drops straight back to the login screen - a
	# black flash and no session, with nothing obvious in the logs.
	#
	# Marking them manual first is what keeps autoremove away from them. This is
	# the whole reason the removal below lists packages one by one instead of
	# passing everything and letting apt decide.
	local p
	for p in libwlroots-0.20-0 libwlroots-0.20 libscenefx-0.5; do
		if dpkg-query -W -f='${Status}' "${p}" 2>/dev/null | grep -q "ok installed"; then
			apt-mark manual "${p}" >>"${LOG_FILE}" 2>&1 || true
		fi
	done

	# Build-only packages, removed explicitly. --autoremove is deliberately NOT
	# used: with the runtime libraries protected above it would be harmless, but
	# the flag is what caused the black screen in the first place, and an
	# explicit list is easier to reason about.
	local -a removable=()
	for p in "${SWAYFX_DEPS_ADDED[@]}"; do
		case "${p}" in
		# Runtime libraries and anything that could pull them out.
		libwlroots-0.20|libscenefx-0.5) continue ;;
		esac
		removable+=("${p}")
	done

	if [[ ${#removable[@]} -gt 0 ]]; then
		ui_dim "  removing ${#removable[@]} build-only package(s)"
		# A timeout because this also runs from the EXIT trap: if apt is holding
		# a lock, waiting on a dead mirror or asking a question, the script would
		# otherwise hang on the way out and the user would see a frozen terminal
		# with no explanation. A skipped cleanup is recoverable, a hung exit is
		# not.
		if command -v timeout >/dev/null 2>&1; then
			timeout 180 apt-get remove -y "${removable[@]}" >>"${LOG_FILE}" 2>&1 || true
		else
			apt-get remove -y "${removable[@]}" >>"${LOG_FILE}" 2>&1 || true
		fi
	fi

	SWAYFX_DEPS_ADDED=()
	return 0
}

# Is the running compositor already swayfx?
swayfx_present() {
	local v
	v="$(sway --version 2>/dev/null | head -1)"
	case "${v}" in
	*swayfx*) return 0 ;;
	esac
	return 1
}

# Build and install swayfx, replacing the distro sway binary.
#
# The distro package stays installed: it owns /usr/share/sway and the man
# pages, and swayfx only overwrites /usr/bin/sway. That keeps `apt remove sway`
# meaningful and means a failed build leaves a working (if blur-less) system.
swayfx_install() {
	if swayfx_present; then
		ui_dim "swayfx already installed ($(sway --version 2>/dev/null | head -1))"
		return 0
	fi

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would build swayfx ${SWAYFX_VERSION} from source and install it over /usr/bin/sway"
		return 0
	fi

	ui_step "Building swayfx ${SWAYFX_VERSION} (the blur fork of sway)"

	# The headers come from sid; see sid_source_ensure().
	sid_source_ensure || return 1

	# Build deps, installed outside the manifest: they are removed again at the
	# end of this function. libwlroots-0.20-dev and libscenefx-0.5-dev come from
	# sid; trixie ships versions swayfx cannot compile against.
	SWAYFX_DEPS_ADDED=()
	if ! pkg-config --exists wlroots-0.20 scenefx-0.5 2>/dev/null; then
		ui_step "installing the swayfx build dependencies"
		swayfx_build_deps_install || return 1
	fi

	local work="${TMPWORK}/swayfx"
	rm -rf "${work}"
	mkdir -p "${work}"

	ui_dim "downloading swayfx ${SWAYFX_VERSION}"
	if ! curl -sSL --compressed -o "${work}/swayfx.tar.gz" "${SWAYFX_URL}"; then
		ui_err "could not download ${SWAYFX_URL}"
		return 1
	fi
	if ! tar -xzf "${work}/swayfx.tar.gz" -C "${work}" 2>/dev/null; then
		ui_err "the swayfx tarball is damaged"
		return 1
	fi

	local src
	src="$(find "${work}" -maxdepth 1 -type d -name 'swayfx-*' | head -1)"
	if [[ -z "${src}" ]]; then
		ui_err "the swayfx source tree is missing"
		return 1
	fi

	ui_dim "configuring"
	if ! (cd "${src}" && meson setup build -Dprefix=/usr -Dwerror=false) >>"${LOG_FILE}" 2>&1; then
		ui_err "meson setup failed for swayfx (see ${LOG_FILE})"
		return 1
	fi

	ui_dim "compiling (this takes a few minutes)"
	if ! (cd "${src}" && ninja -C build) >>"${LOG_FILE}" 2>&1; then
		ui_err "the swayfx build failed (see ${LOG_FILE})"
		return 1
	fi

	# No backup of the distro binary is kept: --uninstall removes swayfx
	# outright rather than reverting to stock sway, so there would be nothing to
	# restore it for. Reinstalling the sway package brings the distro binary
	# back if it is ever wanted.
	if ! install -m 755 "${src}/build/sway/sway" /usr/bin/sway; then
		ui_err "could not install the swayfx binary"
		return 1
	fi
	register_file /usr/bin/sway

	# swaymsg/swaynag/swaybar come from the same build and must match the
	# compositor's IPC; the distro ones are usually compatible, but shipping the
	# matching set removes a class of "version mismatch" surprises.
	for b in swaymsg swaynag swaybar; do
		if [[ -x "${src}/build/${b}/${b}" ]]; then
			install -m 755 "${src}/build/${b}/${b}" "/usr/bin/${b}" 2>/dev/null || true
		fi
	done

	# The distro package is held so an apt upgrade cannot quietly replace
	# swayfx with stock sway again - that would bring the red banner back.
	apt-mark hold sway >>"${LOG_FILE}" 2>&1 || true

	# The compiler and headers have done their job; drop them so the machine is
	# not left with a toolchain it never asked for.
	swayfx_build_deps_remove

	SWAYFX_INSTALLED=1
	ui_ok "swayfx ${SWAYFX_VERSION} installed over /usr/bin/sway"
	return 0
}

# ---------------------------------------------------------------------
#  Optional software (third page of the TUI)
# ---------------------------------------------------------------------
install_optional_software() {
	local any=0
	[[ ${SOFT_ZENNB:-0} -eq 1 || ${SOFT_VLC:-0} -eq 1 || ${SOFT_OBS:-0} -eq 1 || ${SOFT_FCITX:-0} -eq 1 || ${SOFT_OSK:-0} -eq 1 ]] && any=1
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
	if [[ ${SOFT_OSK:-0} -eq 1 ]]; then
		# Accessibility on-screen keyboard. wvkbd is the only one worth
		# installing here: 800 KB, a single package, and it links nothing but
		# libwayland-client plus cairo/pango which the bar already needs.
		# squeekboard pulls 4 packages and 26 MB, onboard pulls 119 and
		# maliit-keyboard 105 MB - all of them far heavier for the same job.
		apt_install "wvkbd" wvkbd || ui_warn "wvkbd could not be installed"
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
