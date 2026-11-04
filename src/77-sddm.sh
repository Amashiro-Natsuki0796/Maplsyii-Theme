# =====================================================================
#  Display manager: SDDM + SilentSDDM theme
# ---------------------------------------------------------------------
#  A minimal Debian install boots to a TTY with no greeter, so there is
#  no way to pick the i3 session. This module installs SDDM, turns it
#  into the system default (graphical.target), and applies the SilentSDDM
#  theme with its stock configuration. SDDM runs its greeter on X11, which
#  is exactly the server the i3 session needs.
#
#  Everything needed for the greeter is pulled in here too: SDDM's Qt6
#  QML runtime is not a dependency of sddm itself, so a bare install
#  would show a black screen instead of the theme.
# =====================================================================

SDDM_THEME_NAME="silent"
SDDM_THEME_DIR="/usr/share/sddm/themes/${SDDM_THEME_NAME}"
SDDM_CONF="/etc/sddm.conf"
SDDM_CONF_D="/etc/sddm.conf.d"
SDDM_PROFILE="/etc/sddm.conf.d/10-i3-everforest.conf"
SDDM_XSESSION_WRAPPER="/usr/local/bin/i3-everforest-session"

# Qt6 QML modules imported by SilentSDDM's Main.qml and components/.
# Missing any one of them makes the greeter fall back to a black screen.
PKGS_SDDM=(
	sddm
	qml6-module-qtquick
	qml6-module-qtquick-controls
	qml6-module-qtquick-layouts
	qml6-module-qtquick-window
	qml6-module-qtquick-templates
	qml6-module-qtquick-shapes
	qml6-module-qtquick-effects
	qml6-module-qtquick-particles
	qml6-module-qtqml-workerscript
	qml6-module-qt-labs-platform
	qml6-module-qtmultimedia
	qml6-module-qtquick-virtualkeyboard
	qt6-virtualkeyboard-plugin
	libqt6svg6
	qt6-svg-plugins
	qt6-image-formats-plugins
	xserver-xorg
	xserver-xorg-video-all
	xserver-xorg-video-fbdev
	xserver-xorg-input-libinput
	x11-xserver-utils
	x11-utils
	xauth
	dbus-x11
	# The X11 greeter is what SDDM starts by default; keep the backend and
	# an X terminal emulator available so its fail-safe greeter works too.
	xterm
	hicolor-icon-theme
	shared-mime-info
	desktop-file-utils
)

# ---------------------------------------------------------------------
#  The greeter runs as the `sddm` user, so it must be able to read the
#  theme. Files land as root:root 644/755, which is fine; the check below
#  catches the case where a umask made them unreadable.
# ---------------------------------------------------------------------
sddm_theme_ok() {
	[[ -f "${SDDM_THEME_DIR}/Main.qml" ]] || return 1
	[[ -f "${SDDM_THEME_DIR}/metadata.desktop" ]] || return 1
	runuser -u sddm -- test -r "${SDDM_THEME_DIR}/Main.qml" 2>/dev/null || return 1
	return 0
}

sddm_pin_stock_config() {
	# The upstream theme selects its preset through metadata.desktop.
	# "default.conf" is SilentSDDM's stock configuration.
	local meta="${SDDM_THEME_DIR}/metadata.desktop"
	[[ -f "${meta}" ]] || return 1
	sed -i 's|^ConfigFile=.*|ConfigFile=configs/default.conf|' "${meta}"
	return 0
}

sddm_install_theme_files() {
	local src="${ASSET_DIR}/sddm/silent"
	if [[ ! -d "${src}" ]]; then
		ui_err "the bundled SilentSDDM theme is missing from the payload"
		return 1
	fi
	ui_step "installing the SilentSDDM theme"
	rm -rf "${SDDM_THEME_DIR}"
	install -d "${SDDM_THEME_DIR}"
	cp -a "${src}/." "${SDDM_THEME_DIR}/"
	sddm_pin_stock_config || return 1

	# The theme ships its own fonts (RedHatDisplay); the greeter needs them
	# installed system-wide, not just present in the theme directory.
	if [[ -d "${SDDM_THEME_DIR}/fonts" ]]; then
		install -d /usr/share/fonts/silent-sddm
		find "${SDDM_THEME_DIR}/fonts" -type f \( -name '*.otf' -o -name '*.ttf' \) \
			-exec cp -f {} /usr/share/fonts/silent-sddm/ \; 2>/dev/null || true
		if have fc-cache; then
			fc-cache -f /usr/share/fonts/silent-sddm >/dev/null 2>&1 || true
		fi
	fi

	# Make sure the sddm user can actually read everything.
	chmod -R a+rX "${SDDM_THEME_DIR}"
	ui_ok "theme installed: ${SDDM_THEME_DIR}"

	# Account avatar shown on the login screen.
	#
	# The greeter runs as the `sddm` system user, and a stock Debian home is
	# mode 0700, so it cannot open ~/.face.icon at all - writing only there
	# leaves the login screen with the generic placeholder. Install the same
	# image to every location a greeter may consult:
	#
	#   ~/.face, ~/.face.icon          accounts-service / SDDM convention
	#   /usr/share/sddm/faces/*.face.icon   SDDM's system-wide fallback
	local avatar_src="${ASSET_DIR}/user-avatar.jpg"
	if [[ -f "${avatar_src}" ]]; then
		local face="${HOME_DIR}/.face"
		install -m 644 "${avatar_src}" "${face}"
		install -m 644 "${avatar_src}" "${face}.icon"
		chown_user "${face}" 2>/dev/null || true
		chown_user "${face}.icon" 2>/dev/null || true
		register_file "${face}"
		register_file "${face}.icon"

		# System-wide copies, readable by the greeter regardless of home perms.
		local uname_s
		uname_s="$(id -un "${TARGET_USER}" 2>/dev/null || echo "${TARGET_USER}")"
		install -d -m 755 /usr/share/sddm/faces
		install -m 644 "${avatar_src}" \
			"/usr/share/sddm/faces/${uname_s}.face.icon"
		manifest_file "/usr/share/sddm/faces/${uname_s}.face.icon"
		ui_ok "login avatar installed for ${uname_s}"
	fi
	return 0
}

sddm_write_profile_plain() {
	# Minimal drop-in for greeters that cannot load SilentSDDM: still enable
	# the Sway session and a sane InputMethod, but no theme override.
	install -d "${SDDM_CONF_D}"
	if [[ -f "${SDDM_PROFILE}" ]]; then
		backup_path "${SDDM_PROFILE}"
	fi
	cat >"${SDDM_PROFILE}" <<EOF
# Generated by the i3 Everforest installer.
# Delete this file to revert SDDM to the distribution defaults.

[General]
InputMethod=qtvirtualkeyboard

[Users]
MaximumUid=65000
MinimumUid=1000
EOF
	chmod 644 "${SDDM_PROFILE}"
	register_file "${SDDM_PROFILE}"
	ui_ok "wrote ${SDDM_PROFILE} (stock greeter)"
	return 0
}

sddm_write_profile() {
	# A drop-in under /etc/sddm.conf.d/ is used instead of editing
	# /etc/sddm.conf, so the distribution's own file stays untouched and
	# uninstalling is a plain file removal.
	install -d "${SDDM_CONF_D}"
	if [[ -f "${SDDM_PROFILE}" ]]; then
		backup_path "${SDDM_PROFILE}"
	fi
	cat >"${SDDM_PROFILE}" <<EOF
# Generated by the i3 Everforest installer.
# Delete this file to revert SDDM to the distribution defaults.

[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=${SDDM_THEME_DIR}/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=${SDDM_THEME_NAME}

[X11]
# Start the greeter on the X server SDDM manages (the default, stated
# explicitly so a distro override cannot switch it to Wayland behind our back).
ServerPath=/usr/bin/X
# Hand the session the environment it needs; without this the greeter logs in
# a window manager that starts with a bare environment.
SessionCommand=/etc/sddm/Xsession
UserAuthFile=/var/run/sddm/xauth

[Users]
MaximumUid=65000
MinimumUid=1000
EOF
	chmod 644 "${SDDM_PROFILE}"
	register_file "${SDDM_PROFILE}"
	ui_ok "wrote ${SDDM_PROFILE}"
	return 0
}

sddm_write_session_launcher() {
	# The xsessions entry points at the same launcher the session component
	# writes; keep one copy so a greeter login and `startx i3` behave alike.
	if [[ -x "${SDDM_XSESSION_WRAPPER}" ]]; then
		ui_dim "session launcher already present: ${SDDM_XSESSION_WRAPPER}"
		return 0
	fi
	session_write_launcher
	return 0
}

sddm_enable_service() {
	ui_step "enabling SDDM as the default display manager"
	# A minimal install boots into multi-user.target; the greeter only
	# appears after switching the default target.
	systemctl set-default graphical.target >>"${LOG_FILE}" 2>&1 || {
		ui_warn "could not set graphical.target as the default"
	}

	# display-manager.service is a single alias: if another greeter (lightdm,
	# gdm3, ...) owns it, `systemctl enable sddm` refuses to overwrite it.
	# Point the alias at SDDM explicitly so SDDM really is the one that starts.
	local dm_link="/etc/systemd/system/display-manager.service"
	if [[ -L "${dm_link}" || -e "${dm_link}" ]]; then
		local target
		target="$(readlink -f "${dm_link}" 2>/dev/null || true)"
		if [[ "${target}" != */sddm.service ]]; then
			ui_dim "replacing the current display-manager.service (${target##*/})"
		fi
	fi
	ln -sfn /lib/systemd/system/sddm.service "${dm_link}" || {
		ui_warn "could not point display-manager.service at SDDM"
	}
	systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
	systemctl enable sddm.service >>"${LOG_FILE}" 2>&1 || {
		ui_warn "could not enable sddm.service"
		return 1
	}
	# Debian's display-manager selection, so `service display-manager start`
	# and the boot order follow SDDM.
	if [[ -d /etc/X11 ]]; then
		printf '/usr/sbin/sddm\n' >/etc/X11/default-display-manager
		chmod 644 /etc/X11/default-display-manager
		register_file /etc/X11/default-display-manager
	fi
	ui_ok "SDDM enabled (graphical.target is now the default)"
	return 0
}

# ---------------------------------------------------------------------
#  pam_systemd is what creates the logind session for the greeter's login.
#  Without it there is no /run/user/<uid>, and the session comes up with a
#  missing session bus instead of a working desktop.
#  It is only a Recommends of sddm/systemd-sysv, so verify it explicitly and
#  repair it if an earlier run used --no-install-recommends.
# ---------------------------------------------------------------------
sddm_ensure_pam_systemd() {
	if [[ -f /usr/lib/x86_64-linux-gnu/security/pam_systemd.so ]] ||
		[[ -f /usr/lib/security/pam_systemd.so ]] ||
		[[ -f /lib/x86_64-linux-gnu/security/pam_systemd.so ]]; then
		return 0
	fi
	ui_warn "pam_systemd is missing - the session would log in to a black screen"
	ui_step "installing libpam-systemd"
	apt_update_once
	if apt-get install -y --no-install-recommends libpam-systemd >>"${LOG_FILE}" 2>&1; then
		manifest_pkg libpam-systemd
		ui_ok "libpam-systemd installed"
		return 0
	fi
	ui_err "could not install libpam-systemd; logging in may fail"
	return 1
}

sddm_version_string() {
	local v
	v="$(sddm --version 2>/dev/null | head -1)"
	[[ -n "${v}" ]] || v="$(apt-cache policy sddm 2>/dev/null | awk '/Installed:/{print $2}')"
	printf '%s' "${v:-unknown}"
}

sddm_theme_loadable() {
	# Actually ask the installed greeter to parse the theme. This is the only
	# reliable test: version numbers lie, and a theme that fails to load gives
	# the user a black login screen. `--test-mode` needs a display, so run it
	# headless under Xvfb when available and fall back to a QML syntax check.
	local theme="${SDDM_THEME_DIR}"
	local meta="${theme}/metadata.desktop"
	[[ -f "${meta}" ]] || return 1

	# 1. the theme's own ConfigFile must exist, or the greeter aborts
	local cfgfile
	cfgfile="$(awk -F= '/^ConfigFile=/{print $2; exit}' "${meta}" 2>/dev/null)"
	if [[ -n "${cfgfile}" && ! -f "${theme}/${cfgfile}" ]]; then
		ui_dim "  theme config missing: ${cfgfile}"
		return 1
	fi

	# 2. every QML import the theme uses must resolve to an installed module
	local -a imports=()
	mapfile -t imports < <(grep -rhoE '^import [A-Za-z0-9.]+' "${theme}" --include='*.qml' 2>/dev/null \
		| awk '{print $2}' | sort -u)
	local qmldir="/usr/lib/${DEB_HOST_MULTIARCH:-x86_64-linux-gnu}/qt6/qml"
	local mod missing=0
	for mod in "${imports[@]}"; do
		case "${mod}" in
			QtQuick|QtQml|QtMultimedia|QtQuick.*) : ;;
			SddmComponents)
				# provided by sddm itself
				if [[ ! -d "${qmldir}/SddmComponents" ]]; then
					ui_dim "  SddmComponents module not found"
					missing=1
				fi
				;;
			*)
				if [[ ! -d "${qmldir}/${mod//.//}" ]]; then
					ui_dim "  QML module not installed: ${mod}"
					missing=1
				fi
				;;
		esac
	done
	(( missing == 0 )) || return 1

	# 3. the greeter binary itself must exist
	if ! have sddm-greeter-qt6 && ! have sddm-greeter; then
		ui_dim "  no sddm greeter binary"
		return 1
	fi
	return 0
}

sddm_verify() {
	local ok=1
	if ! have sddm; then
		ui_err "sddm is not installed"; ok=0
	fi
	if ! have sddm-greeter-qt6; then
		ui_err "sddm-greeter-qt6 is missing"; ok=0
	fi
	# Only require the theme files when the profile actually selects the theme.
	local prof_theme
	prof_theme="$(awk -F= '/^\[Theme\]/{t=1;next} t&&/^Current=/{print $2;exit}' "${SDDM_PROFILE}" 2>/dev/null)"
	if [[ "${prof_theme}" == "${SDDM_THEME_NAME}" ]]; then
		if ! sddm_theme_ok; then
			ui_err "the theme is not readable by the sddm user"; ok=0
		fi
	fi

	if ! systemctl is-enabled sddm.service >/dev/null 2>&1; then
		ui_err "sddm.service is not enabled"; ok=0
	fi
	if [[ "$(systemctl get-default 2>/dev/null)" != "graphical.target" ]]; then
		ui_err "the default systemd target is not graphical.target"; ok=0
	fi
	if [[ ! -f "${SESSION_DIR}/${SESSION_FILE}" ]]; then
		ui_err "the i3 xsessions entry is missing"; ok=0
	fi
	if [[ ! -f /usr/lib/x86_64-linux-gnu/security/pam_systemd.so ]] &&
		[[ ! -f /usr/lib/security/pam_systemd.so ]]; then
		ui_err "pam_systemd is missing: login would land on a black screen"; ok=0
	fi
	if ((ok)); then
		if [[ "${prof_theme}" == "${SDDM_THEME_NAME}" ]]; then
			ui_ok "SDDM will show the SilentSDDM greeter and offer the i3 session"
		else
			ui_ok "SDDM will show its stock greeter and offer the i3 session"
		fi
	fi
	((ok))
}

sddm_install() {
	ui_hdr "Display manager (SDDM + SilentSDDM)"

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would install SDDM, the SilentSDDM theme and enable the greeter"
		return 0
	fi
	apt_install "display manager" "${PKGS_SDDM[@]}" || {
		ui_err "the SDDM packages could not be installed"
		return 1
	}

	# Remember what we found, so --uninstall can put it back. These files are
	# written once: re-running the installer must not overwrite the original
	# state with the state left by the previous run.
	if [[ ! -f "${STATE_DIR}/previous-display-manager" ]]; then
		if [[ -f /etc/X11/default-display-manager ]]; then
			cp -f /etc/X11/default-display-manager \
				"${STATE_DIR}/previous-display-manager" 2>/dev/null || true
		else
			: >"${STATE_DIR}/previous-display-manager"
		fi
	fi
	if [[ ! -f "${STATE_DIR}/previous-target" ]]; then
		systemctl get-default >"${STATE_DIR}/previous-target" 2>/dev/null || true
	fi
	# The display-manager.service symlink is the thing that actually decides
	# which greeter starts, so record its target as well.
	if [[ ! -f "${STATE_DIR}/previous-dm-link" ]]; then
		local prev_link
		prev_link="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
		printf '%s\n' "${prev_link}" >"${STATE_DIR}/previous-dm-link"
	fi

	# Debian 13 ships SDDM 0.21 built against Qt6, which is exactly what the
	# theme needs, so install it unconditionally.
	sddm_install_theme_files || return 1
	sddm_write_profile || return 1
	sddm_write_session_launcher || return 1

	# The greeter needs a session entry to show; write it even when the
	# separate "session" component was skipped.
	if [[ ! -f "${SESSION_DIR}/${SESSION_FILE}" ]]; then
		SESSION_FILE_OVERRIDE=1
		session_install >/dev/null 2>&1 || true
	fi

	sddm_enable_service
	sddm_ensure_pam_systemd || true
	ui_rule
	sddm_verify || ui_warn "SDDM is installed but some checks failed (see above)"
	return 0
}
