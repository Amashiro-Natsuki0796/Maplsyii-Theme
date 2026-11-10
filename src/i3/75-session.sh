# =====================================================================
#  Login session (display manager entry)
# ---------------------------------------------------------------------
#  i3 is an X11 window manager, so the session entry belongs in
#  /usr/share/xsessions and is started through the X session machinery
#  (startx / the display manager's Xsession). The launcher exports the
#  identity variables every desktop-aware program keys off.
# =====================================================================

SESSION_DIR="/usr/share/xsessions"
SESSION_LAUNCHER="/usr/local/bin/i3-everforest-session"

session_write_launcher() {
	local dest="${SESSION_LAUNCHER}"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would write ${dest}"; return 0; fi

	if [[ -e "${dest}" ]]; then backup_path "${dest}"; fi
	cat >"${dest}" <<'LAUNCH'
#!/bin/sh
# Launcher for the i3 (Everforest) X11 session, used by the xsessions entry.
#
# It runs i3 inside a D-Bus session bus so notifications, portals, pulseaudio
# and NetworkManager all reach the same bus, then hands the session over to
# i3. Everything it exports is what GTK/Qt/portal consumers expect on X11.

LOG="/tmp/i3-everforest-session.log"
: >"${LOG}" 2>/dev/null || LOG=/dev/null

say() { printf '%s\n' "$*" | tee -a "${LOG}" >&2; }

export XDG_CURRENT_DESKTOP=i3
export XDG_SESSION_DESKTOP=i3
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=i3
export MOZ_ENABLE_WAYLAND=0
export QT_QPA_PLATFORMTHEME=gtk3
export _JAVA_AWT_WM_NONREPARENTING=1

# A logind session provides /run/user/<uid>. If pam_systemd did not run (for
# example because libpam-systemd was never installed) every XDG consumer
# falls back to a world-readable /tmp and the session comes up half broken.
# Create it so the session can at least run, and record the diagnosis.
UID_NUM="$(id -u)"
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
	export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
fi
if [ ! -d "${XDG_RUNTIME_DIR}" ]; then
	say "warning: ${XDG_RUNTIME_DIR} is missing (no logind session?)"
	if mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null; then
		chmod 700 "${XDG_RUNTIME_DIR}"
		say "warning: created ${XDG_RUNTIME_DIR} as a fallback"
	else
		mkdir -p "/tmp/runtime-${UID_NUM}" 2>/dev/null &&
			chmod 700 "/tmp/runtime-${UID_NUM}" 2>/dev/null &&
			export XDG_RUNTIME_DIR="/tmp/runtime-${UID_NUM}"
		say "warning: falling back to ${XDG_RUNTIME_DIR}"
	fi
fi

say "starting i3 (DISPLAY=${DISPLAY:-unset}, XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR})"

# i3 itself, with the Everforest config. -a updates the X cursor to the
# theme's arrow, which some clients otherwise leave as an X cross.
if [ -x /usr/bin/dbus-run-session ]; then
	exec /usr/bin/dbus-run-session -- /usr/bin/i3 >>"${LOG}" 2>&1
fi
exec /usr/bin/i3 >>"${LOG}" 2>&1
LAUNCH
	chmod 755 "${dest}"
	register_file "${dest}"
	ui_ok "wrote ${dest}"
	return 0
}

session_install() {
	ui_hdr "Login session"
	local dest="${SESSION_DIR}/${SESSION_FILE}"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would write ${dest}"; return 0; fi

	mkdir -p "${SESSION_DIR}"
	# A leftover Wayland entry from the sway installer would keep offering a
	# session that no longer exists; remove it when it is clearly ours.
	if [[ -f "/usr/share/wayland-sessions/${SESSION_FILE}" ]]; then
		rm -f "/usr/share/wayland-sessions/${SESSION_FILE}" 2>/dev/null || true
	fi

	if [[ -e "${dest}" ]]; then backup_path "${dest}"; fi
	cat >"${dest}" <<'DESKTOP'
[Desktop Entry]
Name=i3 (Everforest)
Comment=i3 with the Everforest rice (X11)
Exec=/usr/local/bin/i3-everforest-session
TryExec=/usr/bin/i3
Type=Application
DesktopNames=i3
Keywords=x11;tiling;window manager;i3;
DESKTOP
	chmod 644 "${dest}"
	register_file "${dest}"
	session_write_launcher
	ui_ok "wrote ${dest}"

	# The session list is cached by some greeters; refresh it.
	if have update-desktop-database; then
		update-desktop-database "${SESSION_DIR}" >/dev/null 2>&1 || true
	fi

	local dm=""
	have lightdm && dm="lightdm"
	if [[ -z "${dm}" ]] && have gdm3; then dm="gdm3"; fi
	if [[ -z "${dm}" ]] && have sddm; then dm="sddm"; fi
	if [[ -z "${dm}" ]] && have greetd; then dm="greetd"; fi
	if [[ -n "${dm}" ]]; then
		ui_dim "display manager detected: ${dm} - pick 'i3 (Everforest)' at login"
	else
		ui_dim "no display manager yet: enable the 'sddm' component to get a greeter"
		ui_dim "from a TTY you can also run: startx i3"
	fi
}

# ---------------------------------------------------------------------
#  Optional: install a display manager when the machine boots to a TTY
# ---------------------------------------------------------------------
session_maybe_install_dm() {
	((SESSION)) || return 0
	local active; active="$(systemctl get-default 2>/dev/null || echo unknown)"
	if [[ "${active}" == "graphical.target" ]]; then return 0; fi
	if have lightdm || have gdm3 || have sddm || have greetd; then return 0; fi
	ui_dim "no display manager installed - the session will be available after installing one"
}

session_enable_dm() {
	((SESSION)) || return 0
	local dm=""
	have lightdm && dm="lightdm"
	if [[ -z "${dm}" ]] && have gdm3; then dm="gdm3"; fi
	if [[ -z "${dm}" ]] && have sddm; then dm="sddm"; fi
	if [[ -z "${dm}" ]] && have greetd; then dm="greetd"; fi
	if [[ -z "${dm}" ]]; then return 0; fi
	if systemctl is-enabled "${dm}" >/dev/null 2>&1; then return 0; fi
	ui_step "enabling ${dm} so you can pick the i3 session at login"
	systemctl enable "${dm}" >>"${LOG_FILE}" 2>&1 || ui_warn "could not enable ${dm}"
}
