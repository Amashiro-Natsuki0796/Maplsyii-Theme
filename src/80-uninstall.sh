# =====================================================================
#  Uninstall - restore the machine to its pre-install state
# ---------------------------------------------------------------------
#  Restoring backups runs FIRST, so a file that existed before this
#  script ever ran is never left deleted if something goes wrong.
# =====================================================================

uninstall_restore_backups() {
	local map="${STATE_DIR}/backup-map.tsv"
	if [[ ! -f "${map}" ]]; then
		ui_dim "no backups to restore"
		return 0
	fi
	local orig back n=0
	# Restore in two passes: every recorded original gets its backup back.
	while IFS=$'\t' read -r orig back; do
		[[ -n "${orig}" && -e "${back}" ]] || continue
		mkdir -p "$(dirname "${orig}")"
		rm -rf "${orig}"
		cp -a "${back}" "${orig}"
		ui_dim "restored ${orig}"
		n=$((n + 1))
	done <"${map}"
	((n == 0)) && ui_dim "no backups needed restoring"
	return 0
}

# Paths that existed before the install (recorded in the backup map).
uninstall_backed_up_paths() {
	local map="${STATE_DIR}/backup-map.tsv" p
	[[ -f "${map}" ]] || return 0
	while IFS=$'\t' read -r p _; do
		[[ -n "${p}" ]] && printf '%s\n' "${p}"
	done <"${map}"
}

uninstall_files() {
	[[ -f "${STATE_DIR}/installed-files.list" ]] || { ui_dim "no file list recorded"; return 0; }

	local -A restored=()
	local p
	while IFS= read -r p; do
		[[ -n "${p}" ]] && restored["${p}"]=1
	done < <(uninstall_backed_up_paths)

	local removed=0 skipped=0
	# Reverse order so nested paths are handled before their parents.
	while IFS= read -r p; do
		[[ -n "${p}" ]] || continue
		if [[ -n "${restored[${p}]:-}" ]]; then
			skipped=$((skipped + 1))
			continue
		fi
		if [[ -e "${p}" || -L "${p}" ]]; then
			rm -rf "${p}"
			removed=$((removed + 1))
		fi
	done < <(tac "${STATE_DIR}/installed-files.list")
	ui_dim "removed ${removed} file(s), kept ${skipped} restored from backup"
	return 0
}

uninstall_dirs() {
	local kind path n=0
	[[ -f "${MANIFEST}" ]] || return 0
	while IFS=$'\t' read -r kind path; do
		[[ "${kind}" == "dir" ]] || continue
		[[ -d "${path}" ]] || continue
		rm -rf "${path}"
		ui_dim "removed ${path}"
		n=$((n + 1))
	done <"${MANIFEST}"
	((n == 0)) && ui_dim "no directories to remove"
	return 0
}

uninstall_packages() {
	if [[ ${OPT_KEEP_PACKAGES} -eq 1 ]]; then
		ui_dim "keeping installed packages (--keep-packages)"
		return 0
	fi
	[[ -f "${MANIFEST}" ]] || return 0

	# Packages the script is responsible for, split by whether they existed
	# before it ran. The second list is the default target: removing something
	# the user already had would be surprising. --purge-everything extends the
	# removal to the whole list for a truly clean machine.
	local -a fresh=() everything=()
	local kind path
	while IFS=$'\t' read -r kind path; do
		[[ "${kind}" == "pkg" ]] || continue
		[[ -n "${path}" ]] || continue
		everything+=("${path}")
		if [[ -f "${STATE_DIR}/preinstalled-packages.txt" ]] &&
			grep -qxF "${path}" "${STATE_DIR}/preinstalled-packages.txt"; then
			continue
		fi
		fresh+=("${path}")
	done <"${MANIFEST}"

	local -a pkgs=()
	if [[ ${OPT_PURGE_EVERYTHING} -eq 1 ]]; then
		pkgs=("${everything[@]}")
	else
		pkgs=("${fresh[@]}")
	fi

	if [[ ${#pkgs[@]} -eq 0 ]]; then
		ui_dim "no packages to remove"
		if [[ ${#everything[@]} -gt 0 ]]; then
			ui_dim "  ${#everything[@]} package(s) were already present before the install;"
			ui_dim "  re-run with --purge-everything to remove them too"
		fi
		return 0
	fi

	# Filter to what is actually installed right now, so apt does not fail on
	# a package that is already gone.
	local -a real=()
	local p
	for p in "${pkgs[@]}"; do
		if dpkg-query -W -f='${Status}' "${p}" 2>/dev/null | grep -q "ok installed"; then
			real+=("${p}")
		fi
	done
	if [[ ${#real[@]} -eq 0 ]]; then
		ui_dim "no packages left to remove"
		return 0
	fi

	ui_step "removing ${#real[@]} package(s)"

	# Remove in batches and never let one refusal abort the rest: apt refuses a
	# whole transaction when a single package is protected (sudo, dbus and the
	# X server are common), which used to leave every package in place.
	local -a batch=()
	local failed=() removed=0
	for p in "${real[@]}"; do
		batch+=("${p}")
		# 20 at a time keeps the apt output readable and the retries cheap.
		if [[ ${#batch[@]} -ge 20 ]]; then
			if apt-get remove -y --purge -o Dpkg::Options::=--force-confdef \
				-o Dpkg::Options::=--force-confold "${batch[@]}" >>"${LOG_FILE}" 2>&1; then
				removed=$((removed + ${#batch[@]}))
			else
				failed+=("${batch[@]}")
			fi
			batch=()
		fi
	done
	if [[ ${#batch[@]} -gt 0 ]]; then
		if apt-get remove -y --purge -o Dpkg::Options::=--force-confdef \
			-o Dpkg::Options::=--force-confold "${batch[@]}" >>"${LOG_FILE}" 2>&1; then
			removed=$((removed + ${#batch[@]}))
		else
			failed+=("${batch[@]}")
		fi
	fi

	# Retry the failures one by one, so a single protected package only blocks
	# itself.
	if [[ ${#failed[@]} -gt 0 ]]; then
		ui_dim "retrying ${#failed[@]} package(s) individually"
		local f
		for f in "${failed[@]}"; do
			if apt-get remove -y --purge -o Dpkg::Options::=--force-confdef \
				-o Dpkg::Options::=--force-confold "${f}" >>"${LOG_FILE}" 2>&1; then
				removed=$((removed + 1))
			else
				ui_dim "  could not remove ${f} (protected or a dependency)"
			fi
		done
	fi

	# Dependencies that came in with them and are no longer needed.
	apt-get autoremove -y --purge >>"${LOG_FILE}" 2>&1 || true
	ui_ok "package removal finished (${removed} requested)"
	return 0
}

uninstall_bash_block() {
	local rc="${HOME_DIR}/.bashrc"
	[[ -f "${rc}" ]] || return 0
	if ! grep -qF "# >>> i3-everforest >>>" "${rc}" 2>/dev/null; then
		return 0
	fi
	local tmp
	tmp="$(mktemp)"
	awk '
		/# >>> i3-everforest >>>/ { skip = 1; next }
		/# <<< i3-everforest <<</ { skip = 0; next }
		!skip { print }
	' "${rc}" >"${tmp}"
	install -m 644 "${tmp}" "${rc}"
	rm -f "${tmp}"
	chown "${TARGET_USER}:${TARGET_GROUP}" "${rc}" 2>/dev/null || true
	ui_dim "removed the i3-everforest block from ${rc}"
	return 0
}

uninstall_tidy_dirs() {
	local d
	for d in \
		"${HOME_DIR}/.config/i3" \
		"${HOME_DIR}/.config/i3-everforest" \
		"${HOME_DIR}/.config/kitty" \
		"${HOME_DIR}/.config/foot" \
		"${HOME_DIR}/.config/rofi" \
		"${HOME_DIR}/.config/dunst" \
		"${HOME_DIR}/.config/picom" \
		"${HOME_DIR}/.config/btop/themes"; do
		[[ -d "${d}" ]] || continue
		rmdir "${d}" 2>/dev/null && ui_dim "removed empty ${d}"
	done
	rm -f /usr/share/backgrounds/i3-everforest.jpg 2>/dev/null
	# A stale Wayland entry left behind by an earlier sway install would keep
	# offering a session that no longer exists.
	rm -f /usr/share/wayland-sessions/sway-everforest.desktop 2>/dev/null || true
	sddm_uninstall_restore 2>/dev/null || true
	return 0
}

# ---------------------------------------------------------------------
#  Put the display manager back the way we found it.
# ---------------------------------------------------------------------
sddm_uninstall_restore() {
	[[ ${SDDM_UNINSTALL_DONE:-0} -eq 1 ]] && return 0
	[[ -f "${SDDM_PROFILE}" ]] || return 0
	ui_step "reverting the display manager changes"

	rm -f "${SDDM_PROFILE}" 2>/dev/null && ui_dim "removed ${SDDM_PROFILE}"

	# restore the previous default target, if we changed it
	if [[ -f "${STATE_DIR}/previous-target" ]]; then
		local prev
		prev="$(cat "${STATE_DIR}/previous-target" 2>/dev/null)"
		if [[ -n "${prev}" && "${prev}" != "graphical.target" ]]; then
			systemctl set-default "${prev}" >>"${LOG_FILE}" 2>&1 &&
				ui_dim "default target restored to ${prev}"
		fi
	fi

	# Restore the display-manager.service symlink first: it is what decides
	# which greeter starts. fall back to the Debian selector file.
	if [[ -f "${STATE_DIR}/previous-dm-link" ]]; then
		local prev_link
		prev_link="$(cat "${STATE_DIR}/previous-dm-link" 2>/dev/null)"
		if [[ -n "${prev_link}" && -e "${prev_link}" ]]; then
			ln -sfn "${prev_link}" /etc/systemd/system/display-manager.service 2>/dev/null &&
				ui_dim "display-manager.service restored to ${prev_link##*/}"
		else
			rm -f /etc/systemd/system/display-manager.service 2>/dev/null
			ui_dim "display-manager.service alias removed"
		fi
		systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
	fi

	if [[ -f "${STATE_DIR}/previous-display-manager" ]]; then
		local pdm
		pdm="$(cat "${STATE_DIR}/previous-display-manager" 2>/dev/null | tr -d '[:space:]')"
		if [[ -n "${pdm}" ]]; then
			printf '%s\n' "${pdm}" >/etc/X11/default-display-manager 2>/dev/null || true
			ui_dim "default-display-manager restored to ${pdm}"
		else
			rm -f /etc/X11/default-display-manager 2>/dev/null
			ui_dim "default-display-manager removed (there was none before)"
		fi
	fi
	SDDM_UNINSTALL_DONE=1
	return 0
}

do_uninstall() {
	preflight
	ui_hdr "Uninstall"
	ui_warn "this removes the i3/everforest desktop installed by this script"
	ui_dim "state: ${STATE_DIR}"
	ui_dim "packages are kept unless you drop --keep-packages"

	if [[ ${OPT_YES} -eq 0 && ${INTERACTIVE} -eq 1 ]]; then
		printf '  %sContinue? [y/N]%s ' "${C_FG}" "${C_RESET}"
		local a=""
		IFS= read -r a || a="n"
		if [[ ! "${a}" =~ ^[yY] ]]; then
			ui_dim "cancelled"
			exit 0
		fi
	fi

	# 1. put every pre-existing file back
	uninstall_restore_backups
	# 2. remove files that this script created
	uninstall_files
	# 3. remove directories it created
	uninstall_dirs
	# 4. strip the bash block (restored in step 1: do it again, harmlessly)
	uninstall_bash_block
	# 5. tidy empty directories it may have created
	uninstall_tidy_dirs
	# 6. optionally remove packages
	uninstall_packages

	ui_ok "uninstalled"
	if [[ ${INTERACTIVE} -eq 1 ]]; then
		printf '  %sAlso delete the log and backup directory (%s)? [y/N]%s ' \
			"${C_FG}" "${STATE_DIR}" "${C_RESET}"
		local a=""
		IFS= read -r a || a="n"
		if [[ "${a}" =~ ^[yY] ]]; then
			rm -rf "${STATE_DIR}"
			ui_dim "removed ${STATE_DIR}"
		else
			ui_dim "kept ${STATE_DIR} (delete it manually when you are sure)"
		fi
	fi
	return 0
}
