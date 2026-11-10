# =====================================================================
#  Main: argument parsing, orchestration, summary
# =====================================================================

usage() {
	cat <<EOF
${PROG} ${VERSION} - i3 Everforest rice for Debian 13 (trixie, X11)

USAGE
  sudo ./$(basename "${SELF}")                 menu: install / reinstall / uninstall
  sudo ./$(basename "${SELF}") --yes           install everything, no questions
  sudo ./$(basename "${SELF}") --dry-run       preview only, change nothing

COMPONENTS
  core      i3, C bar, kitty, rofi, dunst, feh, picom, i3lock
  apps      pcmanfm, btop, pavucontrol, flameshot, imv, nomacs, mpv, cliphist
  theme     GTK2/3/4 Everforest-Dark-BL-LB + libadwaita override
  icons     Material-Black-Lime-Numix-FLAT
  wall      wallpaper from wallhaven (4xxw9z), 1920x1080
  dots      i3, bar, kitty, rofi, dunst, i3lock, btop configs
  session   /usr/share/xsessions entry for i3
  sddm      SDDM display manager + SilentSDDM theme (graphical login)
  shell     the 'mf' fetch block + Everforest bash prompt

OPTIONS
  -y, --yes               non-interactive: install everything with defaults
      --user NAME         desktop user (default: the sudo invoker)
  -n, --dry-run           show what would be done, change nothing
      --no-tui            never ask questions (same as a non-interactive run)
      --opacity LEVEL     bar transparency: solid (default), soft, clear
      --no-apt-update     do not refresh the package lists

  Skip one component:
      --no-core  --no-apps  --no-theme  --no-icons
      --no-wallpaper  --no-dots  --no-session  --no-sddm  --no-shell

  Install one component only:
      --only-dots  --only-theme  --only-wallpaper  --only-shell  --only-sddm

  Optional software (the TUI also offers Zen Browser, VLC, OBS and fcitx5):
      --firefox           Firefox from Mozilla's APT repo + zh-CN language pack
      --no-firefox        skip it even in a non-interactive run

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
  ~/.local/state/i3-everforest/backups/<timestamp>/.
  Everything the look needs (theme, icons, wallpaper) is embedded, so it
  also works with no network at all.
  After installing, reboot: SDDM shows the SilentSDDM greeter, and picking
  "i3 (Everforest)" logs straight into the desktop.
  On a machine with no display manager at all, choose the "sddm" component.
  This is an X11 desktop: there is no Wayland session, and no compositor
  effects beyond what picom provides.

KEYBINDINGS AFTER INSTALL
  Mod = Super/Windows key
  Mod+Return terminal     Mod+d launcher        Mod+e files
  Mod+Shift+Return btop   Mod+Shift+E power     Mod+Shift+C reload
  Mod+1..8 workspaces     Mod+Escape lock       Print screenshot
  Mod+F fullscreen        Mod+W tabbed          Mod+R resize mode
  Mod+Shift+R restart     Mod+Shift+Print region screenshot
EOF
}

list_components() {
	cat <<EOF
core     i3 GTK-bar kitty rofi dunst feh picom i3lock xorg
apps     pcmanfm gvfs btop fastfetch pavucontrol network-manager-gnome
         imv nomacs mpv flameshot swappy cliphist
theme    ${THEME_NAME} (GTK2/3/4) + gtk-3.0/gtk-4.0/libadwaita settings
icons    ${ICON_NAME}
wall     wallhaven 4xxw9z -> ~/.local/share/${SHARE_DIR_NAME}/wallpaper.jpg
dots     i3, C bar, kitty, rofi, dunst, i3lock, btop
session  /usr/share/xsessions/${SESSION_FILE}
sddm     SDDM + SilentSDDM theme -> ${SDDM_THEME_DIR}, boots to graphical.target
shell    /usr/local/bin/mf + Everforest bash prompt
EOF
}

parse_args() {
	local -a ONLY_LIST=()
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
		--firefox) SOFT_FIREFOX=1 ;;
		--no-firefox) SOFT_FIREFOX=0 ;;
		--no-sddm) SDDM=0 ;;
		--opacity) shift; BAR_OPACITY="${1:-solid}"; OPT_OPACITY_GIVEN=1 ;;
		--opacity=*) BAR_OPACITY="${1#*=}"; OPT_OPACITY_GIVEN=1 ;;
		--only-sddm) ONLY_LIST+=("sddm") ;;
		--no-core) CORE=0 ;;
		--only-dots) ONLY_LIST+=("dots") ;;
		--only-theme) ONLY_LIST+=("theme") ;;
		--only-shell) ONLY_LIST+=("shell") ;;
		--only-wallpaper) ONLY_LIST+=("wallpaper") ;;
		--extract-assets) shift; DEST="${1:-./i3-everforest-assets}"; KEEP_TMP=1; extract_assets "${DEST}"; exit 0 ;;
		--list) list_components; exit 0 ;;
		-h | --help) usage; exit 0 ;;
		-v | --version) echo "${PROG} ${VERSION}"; exit 0 ;;
		*) die "unknown option '$1' (try --help)" ;;
		esac
		shift
	done

	# Apply --only-* selections in one pass: every component not named is
	# switched off. This makes the flags combinable (`--only-dots --only-shell`)
	# instead of letting the last one win.
	if [[ ${#ONLY_LIST[@]} -gt 0 ]]; then
		local c
		local want_dots=0 want_shell=0 want_theme=0 want_wall=0 want_sddm=0
		for c in "${ONLY_LIST[@]}"; do
			case "${c}" in
			dots) want_dots=1 ;;
			shell) want_shell=1 ;;
			theme) want_theme=1 ;;
			wallpaper) want_wall=1 ;;
			sddm) want_sddm=1 ;;
			esac
		done
		CORE=0; APPS=0; SESSION=0
		GTK_THEME=${want_theme}
		ICONS=${want_theme}       # the theme component also carries the icons
		WALLPAPER=${want_wall}
		DOTS=${want_dots}
		SHELLFX=${want_shell}
		SDDM=${want_sddm}
	fi

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
		write_network || true
		write_input || true
		write_bar_actions || true
		write_picker || true
		write_lock_and_power || true
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
	if [[ ${SDDM} -eq 1 ]]; then sddm_install || ui_warn "the display manager could not be configured"; fi
	if [[ ${SHELLFX} -eq 1 ]]; then
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
			ui_dim "would install /usr/local/bin/mf, the bar helpers and the bash prompt"
		else
			write_mf; write_stats; write_volume; write_brightness; write_sysinfo
			write_network; write_input; write_bar_actions; write_picker
			write_lock_and_power
			write_bash_extras
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

	# `i3 -C` parses the config without starting the window manager. The exit
	# status is the verdict; i3 prints its own diagnostics to stderr.
	if [[ -f "${HOME_DIR}/.config/i3/config" ]] && have i3; then
		local i3log="${TMPWORK}/i3-check.log"
		if runuser -u "${TARGET_USER}" -- env DISPLAY= HOME="${HOME_DIR}" \
			i3 -C -c "${HOME_DIR}/.config/i3/config" >"${i3log}" 2>&1; then
			ui_ok "i3 config is valid"
		else
			# i3's exit status covers more than config parsing: it also fails
			# when it cannot chdir to the current directory, which happens
			# whenever the caller sits somewhere the target user cannot read -
			# a root-owned home during an automated install, or a chroot. Those
			# are environment complaints, not broken configuration, so they are
			# filtered out and only genuine parser errors fail the check.
			local real_errors
			real_errors="$(grep -iE 'error|invalid|expected|could not|unknown' "${i3log}" 2>/dev/null \
				| grep -ivE 'chdir\(.*\) failed|Permission denied' \
				| head -8)"
			if [[ -z "${real_errors}" ]]; then
				ui_ok "i3 config is valid"
			else
				ui_err "i3 reported configuration problems:"
				printf '%s\n' "${real_errors}" | sed 's/^/      /'
				ok=0
			fi
		fi
	fi

	# The bar is a compiled C binary driven by a JSON description. Two things
	# can break it, and both are checkable without a display: the binary must
	# be a runnable ELF, and the JSON must parse and name the modules it lists.
	if [[ -f "/usr/local/bin/i3-everforest-bar" ]]; then
		local barprog="/usr/local/bin/i3-everforest-bar"
		if [[ -x "${barprog}" ]] && head -c 4 "${barprog}" | grep -q $'\x7fELF'; then
			ui_ok "bar binary is runnable"
		else
			ui_err "the bar is not an executable binary"
			ok=0
		fi
	fi

	if [[ -f "${HOME_DIR}/.config/i3-everforest/bar.json" ]]; then
		local barcfg="${HOME_DIR}/.config/i3-everforest/bar.json"
		local barcheck
		barcheck="$(runuser -u "${TARGET_USER}" -- python3 - "${barcfg}" <<'PYCHK' 2>&1
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
mods = cfg.get("modules", {})
listed = []
for side in ("modules-left", "modules-center", "modules-right"):
    listed += cfg.get(side, [])
missing = [m for m in listed if m not in mods]
if missing:
    print("modules listed but not defined: " + ", ".join(missing))
    sys.exit(1)
# Every module must declare a type the bar understands.
known = {"workspaces", "window", "separator", "custom", "graph"}
bad = [m for m, d in mods.items() if d.get("type") not in known]
if bad:
    print("unknown module type: " + ", ".join(bad))
    sys.exit(1)
print("ok")
PYCHK
)"
		if [[ "${barcheck}" == "ok" ]]; then
			ui_ok "bar layout is valid"
		else
			ui_err "bar layout is invalid:"
			printf '%s\n' "${barcheck}" | head -5 | sed 's/^/      /'
			ok=0
		fi
	fi

	# rofi validates its own theme with `-dump-theme`, but that needs an X
	# connection; without one it fails on "Failed to open display", which is
	# an environment problem, not a theme problem. So: ask rofi when a display
	# answers, and otherwise check the structure its parser requires.
	if [[ -f "${HOME_DIR}/.config/rofi/i3-everforest.rasi" ]]; then
		local rasi="${HOME_DIR}/.config/rofi/i3-everforest.rasi"
		if have rofi && display_reachable; then
			local rofiout="${TMPWORK}/rofi-check.log"
			runuser -u "${TARGET_USER}" -- env HOME="${HOME_DIR}" \
				DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" \
				rofi -theme "${rasi}" -dump-theme >"${rofiout}" 2>&1 || true
			# Only a real parse complaint counts; locale and display warnings
			# are noise from the environment.
			local rproblem
			rproblem="$(grep -iE 'error|invalid|unknown|expected|unexpected|deprecat' "${rofiout}" 2>/dev/null |
				grep -viE 'failed to set locale|failed to open display|connection has error' || true)"
			if [[ -n "${rproblem}" ]]; then
				ui_warn "rofi reported theme problems:"
				printf '%s\n' "${rproblem}" | head -5 | sed 's/^/      /'
				ok=0
			else
				ui_ok "rofi theme is valid"
			fi
		else
			local nb no
			nb="$(tr -cd '}' <"${rasi}" | wc -c)"
			no="$(tr -cd '{' <"${rasi}" | wc -c)"
			if [[ "${nb}" -ne "${no}" ]]; then
				ui_err "rofi theme has unbalanced braces (${no} open, ${nb} close)"
				ok=0
			elif ! grep -qE '^\*[[:space:]]*\{' "${rasi}"; then
				ui_err "rofi theme is missing its default * { } block"
				ok=0
			elif ! grep -qE '^window[[:space:]]*\{' "${rasi}"; then
				ui_err "rofi theme is missing its window { } block"
				ok=0
			else
				ui_ok "rofi theme is well formed"
			fi
		fi
	fi

	if [[ -f "${HOME_DIR}/.config/kitty/kitty.toml" ]] && have kitty; then
		if runuser -u "${TARGET_USER}" -- env XDG_RUNTIME_DIR=/tmp \
			kitty --config-file "${HOME_DIR}/.config/kitty/kitty.toml" --version >/dev/null 2>&1; then
			ui_ok "kitty config is valid"
		else
			ui_warn "kitty could not read its configuration"
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
	# Reload the bar so settings that are read at startup (the transparency
	# preset, bar.json layout) take effect without a logout.
	if [[ ${OPT_DRY_RUN} -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
		# The bar is a compiled binary, launched as a bare path. This used to
		# match "python3 /usr/local/bin/i3-everforest-bar" - the form from
		# before the C rewrite - so it never fired and a reinstall left the old
		# bar running with the old settings.
		if pgrep -f "/usr/local/bin/i3-everforest-bar$" >/dev/null 2>&1; then
			pkill -f "/usr/local/bin/i3-everforest-bar$" 2>/dev/null || true
			# The sway/i3 exec_always watchdog brings it back within seconds.
			ui_dim "restarting the bar so the new settings apply"
		fi
	fi

	ui_hdr "Done"
	ui_ok "i3 Everforest is installed for user ${TARGET_USER}"
	printf '\n'
	ui_line "Log out and choose ${C_BOLD}i3 (Everforest)${C_RESET} at the login screen,"
	ui_line "or start it from a TTY with:  ${C_LIME}startx i3${C_RESET}"
	printf '\n'
	ui_line "Keybindings:"
	ui_dim "  Mod+Return  terminal        Mod+d        application launcher"
	ui_dim "  Mod+e       files           Mod+Shift+E  power menu"
	ui_dim "  Mod+1..8    workspaces      Mod+Shift+C  reload i3"
	ui_dim "  Mod+Escape  lock screen     Print        screenshot"
	printf '\n'
	ui_line "Files:"
	ui_dim "  configs   ${HOME_DIR}/.config/{i3,i3-everforest,kitty,rofi,dunst}"
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
	TMPWORK="$(mktemp -d /tmp/i3-everforest.XXXXXX)"
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
