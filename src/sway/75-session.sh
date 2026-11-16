# 75-session.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Login session (display manager entry)
# ---------------------------------------------------------------------
#  The original post had to patch sway.desktop so that
#  XDG_CURRENT_DESKTOP would not be empty. We ship our own entry that
#  exports it explicitly and wraps sway in dbus-run-session.
# =====================================================================

SESSION_DIR="/usr/share/wayland-sessions"

# Move aside the session entries that the distro packages installed.
#
# Only files this installer did not write are touched, and only the two known
# names, so a hand-written session of the user's own stays where it is.
session_hide_package_entries() {
	local f
	for f in sway weston; do
		local src="${SESSION_DIR}/${f}.desktop"
		[[ -f "${src}" ]] || continue
		# Never touch our own file, even if the names ever collide.
		[[ "${f}" == "${SESSION_FILE%.desktop}" ]] && continue
		backup_path "${src}"
		if rm -f "${src}" 2>/dev/null; then
			ui_dim "hid the bundled '${f}' session entry (${src})"
		fi
	done
	return 0
}

session_install() {
	ui_hdr "Login session"
	local dest="${SESSION_DIR}/${SESSION_FILE}"
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would write ${dest}"; return 0; fi

	mkdir -p "${SESSION_DIR}"
	if [[ -e "${dest}" ]]; then backup_path "${dest}"; fi
	cat >"${dest}" <<'DESKTOP'
[Desktop Entry]
Name=Sway
Comment=Sway with the Everforest rice (Wayland, i3-compatible)
Exec=/usr/local/bin/sway-everforest-session
Type=Application
DesktopNames=sway
Keywords=wayland;tiling;sway;i3;
DESKTOP
	chmod 644 "${dest}"
	register_file "${dest}"
	ui_ok "wrote ${dest}"

	# Hide the session entries that come with the packages this installer pulls
	# in. They are not ours and they do not work here:
	#
	#   sway.desktop    ships with `sway`, but on this system /usr/bin/sway is
	#                   swayfx and the configuration uses blur/blur_xray/
	#                   layer_effects. Logging in through this entry starts the
	#                   compositor with the same config, which is fine, but it
	#                   also tempts the user into a session that is not the rice.
	#
	#   weston.desktop  ships with `weston`, which is installed only as the
	#                   kiosk compositor behind the SDDM greeter. It is not a
	#                   desktop the user should pick, and doing so lands in an
	#                   empty weston shell.
	#
	# Both are moved aside rather than deleted, so removing this installer does
	# not lose anything that belonged to a package: --uninstall puts the backups
	# back through the normal backup mechanism.
	session_hide_package_entries

	# Make sure sway is the login shell of nothing weird; just report the
	# available display managers so the message is actionable.
	local dm=""
	have lightdm && dm="lightdm"
	if [[ -z "${dm}" ]] && have gdm3; then dm="gdm3"; fi
	if [[ -z "${dm}" ]] && have sddm; then dm="sddm"; fi
	if [[ -z "${dm}" ]] && have greetd; then dm="greetd"; fi
	if [[ -n "${dm}" ]]; then
		ui_dim "display manager detected: ${dm} - pick 'Sway' at login"
	else
		ui_dim "no display manager yet: enable the 'sddm' component to get a greeter"
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
	ui_step "enabling ${dm} so you can pick the Sway session at login"
	systemctl enable "${dm}" >>"${LOG_FILE}" 2>&1 || ui_warn "could not enable ${dm}"
}

# ---------------------------------------------------------------------
