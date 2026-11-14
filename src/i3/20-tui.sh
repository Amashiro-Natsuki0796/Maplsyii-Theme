# =====================================================================
#  TUI - pure bash, English, line-based so it works everywhere
# ---------------------------------------------------------------------
#  The menu is deliberately line-oriented: the user types a number to
#  toggle a component and presses Enter. This works identically in a
#  console, in a terminal emulator, over SSH, under sudo, and when stdin
#  comes from a pipe - none of which hold true for raw single-key input.
# =====================================================================

tui_detect() {
	if [[ "${OPT_YES}" -eq 1 ]]; then INTERACTIVE=0; return; fi
	if [[ "${OPT_ASSUME_TUI}" == "off" ]]; then INTERACTIVE=0; return; fi
	if [[ -t 0 && -t 1 ]]; then INTERACTIVE=1; else INTERACTIVE=0; fi
}

tui_size() {
	if [[ -t 1 ]]; then
		TUI_COLS="$(tput cols 2>/dev/null || echo 80)"
	else
		TUI_COLS=80
	fi
	if ((TUI_COLS < 72)); then TUI_COLS=72; fi
}

tui_hline() {
	local ch="$1" n="$2" out="" i
	for ((i = 0; i < n; i++)); do out+="${ch}"; done
	printf '%s' "${out}"
}

tui_w() {
	local w=$((TUI_COLS - 4))
	if ((w > 88)); then w=88; fi
	printf '%s' "${w}"
}

opt_short() {
	case "$1" in
	core) printf 'Desktop core    i3, C bar, foot, rofi, dunst, feh' ;;
	apps) printf 'Everyday apps   pcmanfm, btop, pavucontrol, flameshot, imv, nomacs, mpv' ;;
	theme) printf 'GTK theme       Everforest-Dark-BL-LB (+ libadwaita override)' ;;
	icons) printf 'Icon theme      Material-Black-Lime-Numix-FLAT' ;;
	wall) printf 'Wallpaper       wallhaven 4xxw9z, 1920x1080' ;;
	dots) printf 'Dotfiles        i3, C bar, foot, rofi, dunst, i3lock' ;;
	session) printf 'Login session   xsessions entry for i3' ;;
	shell) printf 'Shell extras    mf fetch block + Everforest bash prompt' ;;
	sddm) printf 'SDDM greeter    display manager + SilentSDDM theme' ;;
	esac
}

opt_desc() {
	case "$1" in
	core) printf 'Required. X11 window manager, bar, terminal, launcher, notifications.' ;;
	apps) printf 'The applications wired to the keybindings and the bar.' ;;
	theme) printf 'GTK2/3/4 theme plus gtk-3.0, gtk-4.0 and libadwaita settings.' ;;
	icons) printf 'The lime folders and black application glyphs from the screenshot.' ;;
	wall) printf 'The exact wallpaper from the original post.' ;;
	dots) printf 'All configuration files; existing ones are backed up first.' ;;
	session) printf "Adds 'i3 (Everforest)' to lightdm / gdm3 / sddm / greetd." ;;
	shell) printf 'The two-column fetch block shown in the terminal screenshot.' ;;
	sddm) printf 'Boots to a graphical login; pick the i3 session there.' ;;
	esac
}

opt_state() {
	local v
	case "$1" in
	core) v=$CORE ;; apps) v=$APPS ;; theme) v=$GTK_THEME ;; icons) v=$ICONS ;;
	wall) v=$WALLPAPER ;; dots) v=$DOTS ;; session) v=$SESSION ;; shell) v=$SHELLFX ;;
	sddm) v=$SDDM ;;
	*) v=0 ;;
	esac
	if [[ "${v}" -eq 1 ]]; then printf 'x'; else printf ' '; fi
}

OPT_KEYS=(core apps theme icons wall dots session sddm shell)
TUI_DONE=0

selected_count() {
	local k n=0
	for k in "${OPT_KEYS[@]}"; do
		if [[ "$(opt_state "${k}")" == "x" ]]; then n=$((n + 1)); fi
	done
	printf '%s' "${n}"
}

tui_toggle() {
	case "$1" in
	core) if [[ ${CORE} -eq 1 ]]; then CORE=0; else CORE=1; fi ;;
	apps) if [[ ${APPS} -eq 1 ]]; then APPS=0; else APPS=1; fi ;;
	theme) if [[ ${GTK_THEME} -eq 1 ]]; then GTK_THEME=0; else GTK_THEME=1; fi ;;
	icons) if [[ ${ICONS} -eq 1 ]]; then ICONS=0; else ICONS=1; fi ;;
	wall) if [[ ${WALLPAPER} -eq 1 ]]; then WALLPAPER=0; else WALLPAPER=1; fi ;;
	dots) if [[ ${DOTS} -eq 1 ]]; then DOTS=0; else DOTS=1; fi ;;
	session) if [[ ${SESSION} -eq 1 ]]; then SESSION=0; else SESSION=1; fi ;;
	shell) if [[ ${SHELLFX} -eq 1 ]]; then SHELLFX=0; else SHELLFX=1; fi ;;
	sddm) if [[ ${SDDM} -eq 1 ]]; then SDDM=0; else SDDM=1; fi ;;
	esac
}

tui_render() {
	local w inner i k mark flag banner
	w="$(tui_w)"; inner=$((w - 2))
	ui_clear
	printf '\n'
	printf '%s╭%s╮%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_BOLD}${C_FG}" "${inner}" \
		"  i3 Everforest · Debian 13 installer · v${VERSION}" "${C_LIME}" "${C_RESET}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" \
		"  ${THEME_NAME}  ·  ${ICON_NAME}" "${C_LIME}" "${C_RESET}"
	printf '%s╰%s╯%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '\n'

	for i in "${!OPT_KEYS[@]}"; do
		k="${OPT_KEYS[$i]}"
		mark="$(opt_state "${k}")"
		printf '  %s[%s]%s %s%-6s%s %s\n' \
			"${C_GREEN}" "${mark}" "${C_RESET}" "${C_BOLD}" "$((i + 1))" "${C_RESET}" \
			"$(opt_short "${k}")"
		printf '       %s%s%s\n' "${C_GREY}" "$(opt_desc "${k}")" "${C_RESET}"
	done

	printf '\n  %s%s%s\n' "${C_GREY}" "$(tui_hline '─' 68)" "${C_RESET}"
	printf '  %sselected:%s %s/%s' "${C_GREY}" "${C_RESET}" "$(selected_count)" "${#OPT_KEYS[@]}"
	if [[ -n "${OPT_USER:-}" ]]; then
		printf '    %starget user:%s %s' "${C_GREY}" "${C_RESET}" "${OPT_USER}"
	fi
	printf '\n'
	printf '  %sbar opacity:%s %s   %s(o cycles solid/soft/clear)%s\n' \
		"${C_GREY}" "${C_RESET}" "${C_LIME}${BAR_OPACITY}${C_RESET}" "${C_GREY}" "${C_RESET}"
	printf '\n'
	# Build the hint row from labelled keys: hand-counting printf arguments is
	# how the line ended up printed twice (printf reuses its format when the
	# argument list runs out).
	local -a hints=( "1-9:toggle" "a:all" "n:none" "o:opacity" "i:install" "q:quit" )
	local hint="" pair k d
	for pair in "${hints[@]}"; do
		k="${pair%%:*}"
		d="${pair#*:}"
		hint+="${C_BOLD}${C_LIME}${k}${C_RESET} ${d}    "
	done
	printf '  %s\n' "${hint%    }"
	printf '\n  %s>%s ' "${C_LIME}" "${C_RESET}"
}

# ---------------------------------------------------------------------
#  Action menu - the very first thing an interactive run shows
# ---------------------------------------------------------------------
#  Three mutually exclusive intents. "Install" continues into the component
#  picker; "Reinstall" resets every component to selected first so a previous
#  partial run does not silently skip things; "Uninstall" hands over to the
#  removal path. Keeping this separate from the component menu avoids
#  accidentally reinstalling when the user meant to remove.
TUI_ACTION=""

tui_action_render() {
	local w; w="$(tui_w)"
	printf '
'
	printf '  %s%s%s
' "${C_LIME}" "$(tui_hline '─' "${w}")" "${C_RESET}"
	printf '  %si3 Everforest%s %s· Debian 13 installer · v%s%s
' \
		"${C_BOLD}" "${C_RESET}" "${C_GREY}" "${VERSION}" "${C_RESET}"
	printf '  %s%s%s
' "${C_LIME}" "$(tui_hline '─' "${w}")" "${C_RESET}"
	printf '
'

	if [[ -d "${STATE_DIR}" && -f "${STATE_DIR}/manifest.list" ]]; then
		printf '  %sAn existing installation was found:%s
' "${C_YELLOW}" "${C_RESET}"
		printf '    %s%s%s
' "${C_GREY}" "${STATE_DIR}" "${C_RESET}"
	else
		printf '  %sNo previous installation found.%s
' "${C_GREY}" "${C_RESET}"
	fi
	printf '
'
	printf '  %s1%s  Install      %sinstall the components you pick%s
' \
		"${C_BOLD}${C_LIME}" "${C_RESET}" "${C_GREY}" "${C_RESET}"
	printf '  %s2%s  Reinstall    %sre-select everything and install again%s
' \
		"${C_BOLD}${C_LIME}" "${C_RESET}" "${C_GREY}" "${C_RESET}"
	printf '  %s3%s  Uninstall    %sremove everything this script installed%s
' \
		"${C_BOLD}${C_LIME}" "${C_RESET}" "${C_GREY}" "${C_RESET}"
	printf '
'
	printf '  %s1-3 select    q quit%s
' "${C_GREY}" "${C_RESET}"
	printf '
  %s>%s ' "${C_LIME}" "${C_RESET}"
}

tui_action_menu() {
	local input
	while true; do
		tui_action_render
		input=""
		IFS= read -r input || { printf '\n'; die "standard input closed"; }
		input="${input//[[:space:]]/}"
		case "${input}" in
		1|i|I|install|c|C|continue)
			TUI_ACTION="install"
			return 0
			;;
		2|r|R|reinstall)
			TUI_ACTION="reinstall"
			return 0
			;;
		3|u|U|uninstall|remove)
			TUI_ACTION="uninstall"
			return 0
			;;
		q|Q|quit|exit)
			printf '\n'
			ui_dim "cancelled by user"
			exit 0
			;;
		'')
			continue
			;;
		*)
			printf '\n  %sUnknown choice: %s%s\n' "${C_RED}" "${input}" "${C_RESET}"
			sleep 1
			;;
		esac
	done
}

tui_menu() {
	local input
	while true; do
		tui_render
		input=""
		IFS= read -r input || { printf '\n'; die "standard input closed"; }
		input="${input//[[:space:]]/}"
		if [[ -z "${input}" ]]; then continue; fi

		case "${input}" in
		i|I|install|y|Y|yes|go|ok)
			if [[ "$(selected_count)" -gt 0 ]]; then TUI_DONE=1; return 0; fi
			printf '\n  %sNothing selected.%s\n' "${C_RED}" "${C_RESET}"
			sleep 1
			;;
		q|Q|quit|exit|n|no)
			printf '\n'
			ui_dim "cancelled by user"
			exit 0
			;;
		o|O|opacity)
			case "${BAR_OPACITY}" in
			solid) BAR_OPACITY="soft" ;;
			soft)  BAR_OPACITY="clear" ;;
			*)     BAR_OPACITY="solid" ;;
			esac
			;;
		a|A|all)
			CORE=1 APPS=1 GTK_THEME=1 ICONS=1 WALLPAPER=1 DOTS=1 SESSION=1 SHELLFX=1 SDDM=1
			;;
		none|none!)
			CORE=0 APPS=0 GTK_THEME=0 ICONS=0 WALLPAPER=0 DOTS=0 SESSION=0 SHELLFX=0 SDDM=0
			;;
		*)
			if [[ "${input}" =~ ^[1-9]+$ ]]; then
				local ch idx
				for ((ch = 0; ch < ${#input}; ch++)); do
					idx=$(( ${input:ch:1} - 1 ))
					if ((idx >= 0 && idx < ${#OPT_KEYS[@]})); then
						tui_toggle "${OPT_KEYS[$idx]}"
					fi
				done
			else
				printf '\n  %sUnknown choice: %s%s\n' "${C_RED}" "${input}" "${C_RESET}"
				sleep 1
			fi
			;;
		esac
	done
}

tui_summary() {
	local w inner k row
	w="$(tui_w)"; inner=$((w - 2))
	ui_clear
	printf '\n'
	printf '%s╭%s╮%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_BOLD}${C_FG}" "${inner}" \
		"  Ready to install" "${C_LIME}" "${C_RESET}"
	printf '%s├%s┤%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	for k in "${OPT_KEYS[@]}"; do
		if [[ "$(opt_state "${k}")" == "x" ]]; then
			row="  [x] $(opt_short "${k}")"
			printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREEN}" \
				"${inner}" "${row}" "${C_LIME}" "${C_RESET}"
		fi
	done
	if [[ "$(selected_count)" -eq 0 ]]; then
		printf '%s╰%s╯%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
		ui_err "nothing selected"
		return 1
	fi
	printf '%s├%s┤%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	row="  user:  ${TARGET_USER}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" "${row}" "${C_LIME}" "${C_RESET}"
	row="  log:   ${LOG_FILE}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" "${row}" "${C_LIME}" "${C_RESET}"
	row="  undo:  $(basename "${SELF}") --uninstall"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" "${row}" "${C_LIME}" "${C_RESET}"
	row="  bar transparency: ${BAR_OPACITY}  (change with --opacity soft|clear)"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" "${row}" "${C_LIME}" "${C_RESET}"
	local extra=""
	[[ ${SOFT_FIREFOX:-0} -eq 1 ]] && extra+="firefox "
	[[ ${SOFT_ZENNB:-0} -eq 1 ]] && extra+="zen "
	[[ ${SOFT_VLC:-0} -eq 1 ]] && extra+="vlc "
	[[ ${SOFT_OBS:-0} -eq 1 ]] && extra+="obs "
	[[ ${SOFT_FCITX:-0} -eq 1 ]] && extra+="fcitx5 "
	[[ ${SOFT_OSK:-0} -eq 1 ]] && extra+="osk "
	row="  extra software: ${extra:-none}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" "${row}" "${C_LIME}" "${C_RESET}"
	printf '%s╰%s╯%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '\n  %sProceed? [Y/n]%s ' "${C_FG}" "${C_RESET}"

	local ans=""
	IFS= read -r ans || ans=""
	if [[ "${ans}" =~ ^[nN] ]]; then return 1; fi
	return 0
}

# ---------------------------------------------------------------------
#  Third page: extra software
# ---------------------------------------------------------------------
#  OPT keys for the optional applications. Each entry is "key|label|hint".
OPT_SOFT_KEYS=( firefox zennb vlc obs fcitx osk )
SOFT_FIREFOX=0
SOFT_ZENNB=0
SOFT_VLC=0
SOFT_OBS=0
SOFT_FCITX=0
SOFT_OSK=0

soft_state() {
	case "$1" in
	zennb) [[ ${SOFT_ZENNB} -eq 1 ]] && printf 'x' || printf ' ' ;;
	firefox) [[ ${SOFT_FIREFOX} -eq 1 ]] && printf 'x' || printf ' ' ;;
	vlc)   [[ ${SOFT_VLC} -eq 1 ]] && printf 'x' || printf ' ' ;;
	obs)   [[ ${SOFT_OBS} -eq 1 ]] && printf 'x' || printf ' ' ;;
	fcitx) [[ ${SOFT_FCITX} -eq 1 ]] && printf 'x' || printf ' ' ;;
	osk)   [[ ${SOFT_OSK} -eq 1 ]] && printf 'x' || printf ' ' ;;
	esac
}

soft_set() {
	local v="$2"
	case "$1" in
	zennb) SOFT_ZENNB=${v} ;;
	firefox) SOFT_FIREFOX=${v} ;;
	vlc)   SOFT_VLC=${v} ;;
	obs)   SOFT_OBS=${v} ;;
	fcitx) SOFT_FCITX=${v} ;;
	osk)   SOFT_OSK=${v} ;;
	esac
}

soft_short() {
	case "$1" in
	firefox) printf 'Firefox        from Mozilla repo, with zh-CN locale' ;;
	zennb) printf 'Zen Browser    private, Firefox-based (official installer)' ;;
	vlc)   printf 'VLC            media player' ;;
	obs)   printf 'OBS Studio     screen recording and streaming' ;;
	fcitx) printf 'fcitx5         Chinese pinyin input method' ;;
	osk)   printf 'Screen keyboard onboard: on-screen keyboard for touch and pointer' ;;
	esac
}

soft_desc() {
	case "$1" in
	firefox) printf 'Mozilla APT repo (key fingerprint verified) + firefox-l10n-zh-cn.' ;;
	zennb) printf 'Official installer: curl -fsSL https://updates.zen-browser.app/install.sh | bash' ;;
	vlc)   printf 'Plays almost every audio and video format.' ;;
	obs)   printf 'X11 capture; records the screen through the X composite extension.' ;;
	fcitx) printf 'Includes fcitx5-chinese-addons (pinyin) and the Qt/GTK modules.' ;;
	osk)   printf 'Accessibility: X11 has no lightweight option; toggled from the bar IME menu.' ;;
	esac
}

soft_count() {
	local n=0 k
	for k in "${OPT_SOFT_KEYS[@]}"; do
		[[ "$(soft_state "${k}")" == "x" ]] && n=$((n + 1))
	done
	printf '%s' "${n}"
}

tui_soft_render() {
	local w inner i k mark
	w="$(tui_w)"; inner=$((w - 2))
	ui_clear
	printf '\n'
	printf '%s╭%s╮%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_BOLD}${C_FG}" "${inner}" \
		"  Optional software" "${C_LIME}" "${C_RESET}"
	printf '%s│%s%-*s%s│%s\n' "${C_LIME}" "${C_RESET}${C_GREY}" "${inner}" \
		"  Nothing here is required; press Enter to keep the defaults" "${C_LIME}" "${C_RESET}"
	printf '%s╰%s╯%s\n' "${C_LIME}" "$(tui_hline '─' "${inner}")" "${C_RESET}"
	printf '\n'

	for i in "${!OPT_SOFT_KEYS[@]}"; do
		k="${OPT_SOFT_KEYS[$i]}"
		mark="$(soft_state "${k}")"
		printf '  %s[%s]%s %s%-6s%s %s\n' \
			"${C_GREEN}" "${mark}" "${C_RESET}" "${C_BOLD}" "$((i + 1))" "${C_RESET}" \
			"$(soft_short "${k}")"
		printf '       %s%s%s\n' "${C_GREY}" "$(soft_desc "${k}")" "${C_RESET}"
	done

	printf '\n  %s%s%s\n' "${C_GREY}" "$(tui_hline '─' 68)" "${C_RESET}"
	printf '  %sselected:%s %s/%s\n' "${C_GREY}" "${C_RESET}" "$(soft_count)" "${#OPT_SOFT_KEYS[@]}"
	printf '\n'
	local -a hints=( "1-6:toggle" "a:all" "n:none" "Enter:continue" "b:back" )
	local hint="" pair keyk desc
	for pair in "${hints[@]}"; do
		keyk="${pair%%:*}"; desc="${pair#*:}"
		hint+="${C_BOLD}${C_LIME}${keyk}${C_RESET} ${desc}    "
	done
	printf '  %s\n' "${hint%    }"
	printf '\n  %s>%s ' "${C_LIME}" "${C_RESET}"
}

tui_soft_menu() {
	local input
	while true; do
		tui_soft_render
		input=""
		IFS= read -r input || { printf '\n'; return 0; }
		input="${input//[[:space:]]/}"
		case "${input}" in
		"")
			return 0
			;;
		b|B|back)
			return 2
			;;
		a|A|all)
			SOFT_FIREFOX=1; SOFT_ZENNB=1; SOFT_VLC=1; SOFT_OBS=1; SOFT_FCITX=1; SOFT_OSK=1
			;;
		n|N|none)
			SOFT_FIREFOX=0; SOFT_ZENNB=0; SOFT_VLC=0; SOFT_OBS=0; SOFT_FCITX=0; SOFT_OSK=0
			;;
		*)
			if [[ "${input}" =~ ^[1-6]+$ ]]; then
				local ch idx
				for ((ch = 0; ch < ${#input}; ch++)); do
					idx=$(( ${input:ch:1} - 1 ))
					local key="${OPT_SOFT_KEYS[$idx]}"
					if [[ "$(soft_state "${key}")" == "x" ]]; then
						soft_set "${key}" 0
					else
						soft_set "${key}" 1
					fi
				done
			fi
			;;
		esac
	done
}

