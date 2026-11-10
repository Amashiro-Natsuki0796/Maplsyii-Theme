# 90-main.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Main: argument parsing, orchestration, summary
# =====================================================================

usage() {
	cat <<EOF
${PROG} ${VERSION} - Sway Everforest rice for Debian 13 (trixie)

USAGE
  sudo ./$(basename "${SELF}")                 menu: install / reinstall / uninstall
  sudo ./$(basename "${SELF}") --yes           install everything, no questions
  sudo ./$(basename "${SELF}") --dry-run       preview only, change nothing

COMPONENTS
  core      sway, waybar, foot, wofi, mako, swaybg, swaylock, swayidle
  apps      pcmanfm, btop, pavucontrol, grim, slurp, wlogout, cliphist, swappy
  theme     GTK2/3/4 Everforest-Dark-BL-LB + libadwaita override
  icons     Material-Black-Lime-Numix-FLAT
  wall      wallpaper from wallhaven (4xxw9z), 1920x1080
  dots      sway, waybar, foot, wofi, mako, swaylock, btop configs
  session   /usr/share/wayland-sessions entry for sway
  sddm      SDDM display manager + SilentSDDM theme (graphical login)
  shell     the 'mf' fetch block + Everforest bash prompt

OPTIONS
  -y, --yes               non-interactive: install everything with defaults
      --user NAME         desktop user (default: the sudo invoker)
  -n, --dry-run           show what would be done, change nothing
      --no-tui            never ask questions (same as a non-interactive run)
      --opacity LEVEL     waybar transparency: solid (default), soft, clear
      --no-apt-update     do not refresh the package lists

  Skip one component:
      --no-core  --no-apps  --no-theme  --no-icons
      --no-wallpaper  --no-dots  --no-session  --no-sddm  --no-shell

  Install one component only:
      --only-dots  --only-theme  --only-wallpaper  --only-shell  --only-sddm

  Remove / inspect:
  -u, --uninstall         remove everything this script installed
      --keep-packages     with --uninstall: leave the apt packages alone
      --purge-everything  with --uninstall: also remove packages that were
                          already installed before this script ran
      --extract-assets D  unpack the bundled assets into D and exit
      --list              print the component list and exit
  -h, --help              this help
  -v, --version           print the version

NOTES
  Run it as root (sudo). The desktop user is the account that invoked sudo,
  or whatever you pass with --user.

  An interactive run starts by asking what you want to do:
      1 Install     pick components and install them
      2 Reinstall   re-select everything, then install again
      3 Uninstall   remove everything this script installed
  Pass --yes, --uninstall or --dry-run to skip that question.

  The installer is idempotent: running it twice does not duplicate anything,
  and every file it overwrites is backed up under
  ~/.local/state/sway-everforest/backups/<timestamp>/.
  Everything the look needs (theme, icons, wallpaper) is embedded, so it
  also works with no network at all.
  After installing, reboot: SDDM shows the SilentSDDM greeter, and picking
  "Sway (Everforest)" logs straight into the desktop.
  On a machine with no display manager at all, choose the "sddm" component.

KEYBINDINGS AFTER INSTALL
  Mod = Super/Windows key
  Mod+Return terminal     Mod+d launcher        Mod+e files
  Mod+Shift+Return btop   Mod+Shift+E power     Mod+Shift+C reload
  Mod+1..8 workspaces     Mod+Escape lock       Print screenshot
  Mod+F fullscreen        Mod+W tabbed          Mod+R resize mode
EOF
}

list_components() {
	cat <<EOF
core     sway foot wofi swaybg swayidle swaylock mako xwayland
apps     pcmanfm gvfs btop fastfetch pavucontrol network-manager-gnome
         imv nomacs mpv
         wlogout swappy cliphist
theme    ${THEME_NAME} (GTK2/3/4) + gtk-3.0/gtk-4.0/libadwaita settings
icons    ${ICON_NAME}
wall     wallhaven 4xxw9z -> ~/.local/share/${SHARE_DIR_NAME}/wallpaper.jpg
dots     sway, waybar, alacritty, wofi, mako, swaylock, btop
session  /usr/share/wayland-sessions/${SESSION_FILE}
sddm     SDDM + SilentSDDM theme -> ${SDDM_THEME_DIR}, boots to graphical.target
shell    /usr/local/bin/mf + Everforest bash prompt
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-y | --yes) OPT_YES=1 ;;
		-u | --uninstall) OPT_UNINSTALL=1 ;;
		-n | --dry-run) OPT_DRY_RUN=1 ;;
		--keep-packages) OPT_KEEP_PACKAGES=1 ;;
		--purge-everything) OPT_PURGE_EVERYTHING=1 ;;
		--no-apt-update) OPT_APT_UPDATE=0 ;;
		--user) shift; OPT_USER="${1:-}" ;;
		--user=*) OPT_USER="${1#*=}" ;;
		--no-tui) OPT_ASSUME_TUI=off ;;
		--no-apps) APPS=0 ;;
		--no-theme) GTK_THEME=0 ;;
		--no-icons) ICONS=0 ;;
		--no-wallpaper) WALLPAPER=0 ;;
		--no-dots) DOTS=0 ;;
		--no-session) SESSION=0 ;;
		--no-shell) SHELLFX=0 ;;
		--no-sddm) SDDM=0 ;;
		--opacity) shift; BAR_OPACITY="${1:-solid}" ;;
		--opacity=*) BAR_OPACITY="${1#*=}" ;;
		--only-sddm) CORE=0 APPS=0 GTK_THEME=0 ICONS=0 WALLPAPER=0 SESSION=0 SHELLFX=0 DOTS=0 SDDM=1 ;;
		--no-core) CORE=0 ;;
		--only-dots) CORE=0 APPS=0 GTK_THEME=0 ICONS=0 WALLPAPER=0 SESSION=0 SHELLFX=0 DOTS=1 ;;
		--only-theme) CORE=0 APPS=0 GTK_THEME=1 ICONS=1 WALLPAPER=0 SESSION=0 SHELLFX=0 DOTS=0 ;;
		--only-shell) CORE=0 APPS=0 GTK_THEME=0 ICONS=0 WALLPAPER=0 SESSION=0 SHELLFX=1 DOTS=0 ;;
		--only-wallpaper) CORE=0 APPS=0 GTK_THEME=0 ICONS=0 WALLPAPER=1 SESSION=0 SHELLFX=0 DOTS=0 ;;
		--extract-assets) shift; DEST="${1:-./sway-everforest-assets}"; KEEP_TMP=1; extract_assets "${DEST}"; exit 0 ;;
		--list) list_components; exit 0 ;;
		-h | --help) usage; exit 0 ;;
		-v | --version) echo "${PROG} ${VERSION}"; exit 0 ;;
		*) die "unknown option '$1' (try --help)" ;;
		esac
		shift
	done

	case "${BAR_OPACITY}" in
	solid|soft|clear) : ;;
	*) die "invalid --opacity '${BAR_OPACITY}' (use solid, soft or clear)" ;;
	esac
}


snapshot_packages() {
	# Remember what was already installed, so --uninstall only removes
	# the packages that this script added.
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then return 0; fi
	mkdir -p "${STATE_DIR}"
	dpkg-query -W -f='${Package}\n' 2>/dev/null | sort -u >"${STATE_DIR}/preinstalled-packages.txt"
}

install_flow() {
	preflight
	snapshot_packages

	tui_summary_preview

	ui_hdr "Installing"
	ui_line "target user : ${TARGET_USER}"
	ui_line "components  : $(selected_list)"
	ui_rule

	if [[ ${CORE} -eq 1 || ${APPS} -eq 1 || ${ICONS} -eq 1 || ${GTK_THEME} -eq 1 || ${SDDM} -eq 1 ]]; then
		install_packages
	fi

	# Optional third-page software is independent of the component selection.
	install_optional_software || true

	if [[ ${GTK_THEME} -eq 1 || ${ICONS} -eq 1 || ${WALLPAPER} -eq 1 || ${SDDM} -eq 1 || ${DOTS} -eq 1 ]]; then
		assets_prepare || ui_warn "continuing without bundled assets"
	fi

	if [[ ${DOTS} -eq 1 ]]; then
		fonts_install || true
		write_stats || true
		write_volume || true
		write_brightness || true
		write_sysinfo || true
		write_bar_actions || true
		write_picker || true
	fi

	if [[ ${GTK_THEME} -eq 1 ]]; then theme_install; fi
	if [[ ${ICONS} -eq 1 ]]; then
		icons_install || true
		icons_install_overrides || true
	fi
	if [[ ${WALLPAPER} -eq 1 ]]; then wallpaper_install || true; fi
	if [[ ${DOTS} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would write the configuration files"; else dotfiles_install; fi
	fi
	if [[ ${SESSION} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then ui_dim "would write ${SESSION_DIR}/${SESSION_FILE}"; else session_install; fi
	fi
	# GPU parameters must land before the display manager picks its backend:
	# the Wayland greeter needs DRM atomic modesetting, which on CIK hardware
	# only exists once amdgpu is selected on the kernel command line.
	if [[ ${CORE} -eq 1 ]]; then install_gpu || ui_warn "GPU configuration was incomplete"; fi

	# Repair tool for the Wayland greeter. The installer never edits the kernel
	# command line itself, because a bad driver switch leaves no display; this
	# puts the tool on PATH so the user can run it from a working session.
	if [[ ${DOTS} -eq 1 || ${SHELLFX} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
			ui_dim "would install /usr/local/bin/sway-everforest-fix-grub"
		else
			write_fix_grub || true
			write_notify_log || true
		fi
	fi

	if [[ ${SDDM} -eq 1 ]]; then sddm_install || ui_warn "the display manager could not be configured"; fi
	if [[ ${SHELLFX} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
			ui_dim "would install /usr/local/bin/mf, the waybar stats helper and the bash prompt"
		else
			write_mf; write_stats; write_volume; write_brightness; write_sysinfo
			write_bar_actions; write_picker; write_bash_extras
		fi
	fi

	if [[ ${GTK_THEME} -eq 1 || ${ICONS} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
			ui_dim "would apply the GTK settings"
		else
			gtk_apply_settings
			theme_guard_install || true
		fi
	fi

	if [[ ${OPT_DRY_RUN} -ne 1 && ${SDDM} -ne 1 ]]; then session_enable_dm || true; fi

	if [[ ${OPT_DRY_RUN} -ne 1 ]]; then
		validate_install || ui_warn "configuration validation reported problems (see above)"
	fi

	finalize_manifest
	print_summary
}

selected_list() {
	local out=()
	if [[ ${CORE} -eq 1 ]]; then out+=("core"); fi
	if [[ ${APPS} -eq 1 ]]; then out+=("apps"); fi
	if [[ ${GTK_THEME} -eq 1 ]]; then out+=("theme"); fi
	if [[ ${ICONS} -eq 1 ]]; then out+=("icons"); fi
	if [[ ${WALLPAPER} -eq 1 ]]; then out+=("wallpaper"); fi
	if [[ ${DOTS} -eq 1 ]]; then out+=("dotfiles"); fi
	if [[ ${SESSION} -eq 1 ]]; then out+=("session"); fi
	if [[ ${SHELLFX} -eq 1 ]]; then out+=("shell"); fi
	if [[ ${SDDM} -eq 1 ]]; then out+=("sddm"); fi
	printf '%s' "${out[*]:-none}"
}

tui_summary_preview() {
	ui_hdr "Plan"
	local k
	for k in "${OPT_KEYS[@]}"; do
		if [[ "$(opt_state "${k}")" == "x" ]]; then
			ui_ok "$(opt_short "${k}")"
		fi
	done
	ui_rule
}

finalize_manifest() {
	[[ -f "${MANIFEST}.new" ]] || return 0
	if [[ -f "${MANIFEST}" ]]; then
		# keep the older entries: an install may be repeated
		cat "${MANIFEST}" "${MANIFEST}.new" | sort -u >"${MANIFEST}.tmp"
		mv "${MANIFEST}.tmp" "${MANIFEST}"
	else
		mv "${MANIFEST}.new" "${MANIFEST}"
	fi
	chown_user "${STATE_DIR}"
}

# ---------------------------------------------------------------------
#  Validation: prove the generated configuration actually loads
# ---------------------------------------------------------------------
validate_install() {
	ui_hdr "Validation"
	local ok=1

	# sway -C parses the config without starting the compositor.
	# A missing wallpaper file is a runtime concern, not a syntax error,
	# so those messages are filtered out of the verdict.
	if [[ -f "${HOME_DIR}/.config/sway/config" ]] && have sway; then
			local swaylog="${TMPWORK}/sway-check.log"
		runuser -u "${TARGET_USER}" -- env XDG_RUNTIME_DIR=/tmp \
			sway -C -c "${HOME_DIR}/.config/sway/config" >"${swaylog}" 2>&1 || true
		# `sway -C` validates the config and then still tries to bring up a
		# backend, so on a machine with no usable seat (container, chroot,
		# headless builder) it reports seat/DRM/tty errors that have nothing
		# to do with the configuration. Only config-parser complaints count.
		local real_errors
		real_errors="$(grep -i "\[ERROR\]" "${swaylog}" 2>/dev/null \
			| grep -iE "config|unknown command|invalid|parse" \
			| grep -iv "unable to access background file" \
			| grep -iv "error on line .* background" \
			| grep -iv "error(s) loading config" || true)"
		if [[ -z "${real_errors}" ]]; then
			ui_ok "sway config is valid"
		else
			ui_err "sway reported configuration problems:"
			printf '%s\n' "${real_errors}" | head -8 | sed 's/^/      /'
			ok=0
		fi
	fi

	# waybar config is JSONC; strip full-line comments and parse with jq
	if [[ -f "${HOME_DIR}/.config/waybar/config.jsonc" ]] && have jq; then
		if sed 's:^[[:space:]]*//.*$::' "${HOME_DIR}/.config/waybar/config.jsonc" | jq -e . >/dev/null 2>&1; then
			ui_ok "waybar config is valid JSON"
		else
			ui_err "waybar config is not valid JSON"; ok=0
		fi
	fi

	if [[ -f "${HOME_DIR}/.config/alacritty/alacritty.toml" ]] && have alacritty; then
		if runuser -u "${TARGET_USER}" -- env XDG_RUNTIME_DIR=/tmp \
			alacritty --config-file "${HOME_DIR}/.config/alacritty/alacritty.toml" --version >/dev/null 2>&1; then
			ui_ok "alacritty config is valid"
		else
			ui_warn "alacritty could not read its configuration"
			ok=0
		fi
	fi

	if [[ ${ICONS} -eq 1 ]]; then
		if [[ -f "/usr/share/icons/${ICON_NAME}/index.theme" ]]; then
			ui_ok "icon theme present: ${ICON_NAME}"
		else
			ui_err "icon theme missing"; ok=0
		fi
	fi
	if [[ ${GTK_THEME} -eq 1 ]]; then
		if [[ -f "/usr/share/themes/${THEME_NAME}/gtk-3.0/gtk.css" ]]; then
			ui_ok "gtk theme present: ${THEME_NAME}"
		else
			ui_err "gtk theme missing"; ok=0
		fi
	fi
	((ok)) || return 1
	return 0
}

print_summary() {
	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_hdr "Dry run finished"
		ui_ok "nothing was changed - this was a preview"
		printf '\n'
		ui_dim "re-run without -n/--dry-run to install"
		printf '\n'
		return 0
	fi
	ui_hdr "Done"
	ui_ok "Sway Everforest is installed for user ${TARGET_USER}"
	printf '\n'
	ui_line "Log out and choose ${C_BOLD}Sway (Everforest)${C_RESET} at the login screen,"
	ui_line "or start it from a TTY with:  ${C_LIME}sway${C_RESET}"
	printf '\n'
	ui_line "Keybindings:"
	ui_dim "  Mod+Return  terminal        Mod+d        application launcher"
	ui_dim "  Mod+e       files           Mod+Shift+E  power menu"
	ui_dim "  Mod+1..8    workspaces      Mod+Shift+C  reload sway"
	ui_dim "  Mod+Escape  lock screen     Print        screenshot"
	printf '\n'
	ui_line "Files:"
	ui_dim "  configs   ${HOME_DIR}/.config/{sway,waybar,alacritty,wofi,mako,swaylock}"
	ui_dim "  wallpaper ${HOME_DIR}/.local/share/${SHARE_DIR_NAME}/wallpaper.jpg"
	ui_dim "  manifest  ${MANIFEST}"
	ui_dim "  log       ${LOG_FILE}"
	ui_dim "  backups   ${BACKUP_DIR}"
	printf '\n'
	ui_line "Undo everything with:  ${C_LIME}sudo $(basename "${SELF}") --uninstall${C_RESET}"
	printf '\n'
}

main() {
	setup_colors
	LOG_FILE=""
	parse_args "$@"
	tui_detect
	tui_size

	# Scratch space for downloads/builds
	TMPWORK="$(mktemp -d /tmp/sway-everforest.XXXXXX)"
	chmod 755 "${TMPWORK}"

	# Which directory holds pre-extracted assets (development runs)
	SCRIPT_ASSET_DIR=""
	if [[ -d "$(dirname "${SELF}")/assets" ]]; then
		SCRIPT_ASSET_DIR="$(dirname "${SELF}")/assets"
	fi

	if [[ ${OPT_UNINSTALL} -eq 1 ]]; then
		do_uninstall
		exit 0
	fi

	if [[ ${INTERACTIVE} -eq 1 ]]; then
		# Resolve the user up front so the menu and summary can show the
		# real home directory, state directory and log path.
		resolve_target_user

		# First question is the intent: install, reinstall or remove.
		tui_action_menu
		case "${TUI_ACTION}" in
		uninstall)
			do_uninstall
			exit 0
			;;
		reinstall)
			# Start from a clean slate so nothing silently stays skipped
			# from a previous partial run.
			CORE=1 APPS=1 GTK_THEME=1 ICONS=1 WALLPAPER=1 \
				DOTS=1 SESSION=1 SHELLFX=1 SDDM=1
			;;
		esac

		tui_menu
		# Third page: optional software. Returning 2 means "back", which
		# reopens the component page instead of losing the choices.
		local soft_rc
		while true; do
			tui_soft_menu
			soft_rc=$?
			[[ ${soft_rc} -eq 2 ]] && { tui_menu; continue; }
			break
		done
		tui_summary || exit 0
	else
		INTERACTIVE=0
	fi

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_hdr "Dry run"
		ui_warn "no changes will be made"
	fi

	if [[ ${INTERACTIVE} -eq 1 ]]; then
		install_flow
	else
		# non-interactive: still print the plan for the log
		install_flow
	fi
}

main "$@"
# The asset payload is appended below this line by build.sh.
exit 0
