# 70-shell.sh
# ---------------------------------------------------------------------
# =====================================================================
#  Shell extras: the "mf" fetch script and the Everforest prompt
# =====================================================================

write_mf() {
	local dest="/usr/local/bin/mf" tmp
	tmp="$(mktemp)"
	cat >"${tmp}" <<'MFSCRIPT'
#!/usr/bin/env bash
# mf - minimal fetch for the Everforest Sway rice (Debian)
# Stand-in for the neofetch block in the original screenshot.

reset=$'\033[0m'
bold=$'\033[1m'
blue=$'\033[38;2;127;187;179m'
green=$'\033[38;2;167;192;128m'
fg=$'\033[38;2;211;198;170m'
lime=$'\033[38;2;185;255;102m'
yellow=$'\033[38;2;219;188;127m'

have() { command -v "$1" >/dev/null 2>&1; }

distro="Debian GNU/Linux"; ver=""
if [[ -r /etc/os-release ]]; then
	. /etc/os-release
	distro="${NAME:-$distro}"
	ver="${VERSION_ID:-}"
fi

kernel="$(uname -r)"

up_s="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
d=$((up_s / 86400)); h=$(((up_s % 86400) / 3600)); m=$(((up_s % 3600) / 60))
if   ((d > 0)); then uptime="${d} days, ${h} hours, ${m} minutes"
elif ((h > 0)); then uptime="${h} hours, ${m} minutes"
else uptime="${m} minutes"; fi

pkgs="$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l)"

de="${XDG_CURRENT_DESKTOP:-sway}"
[[ -z "$de" ]] && de="sway"
case "${de,,}" in
	*sway*) de="sway" ;;
esac
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then sess="wayland"; else sess="x11"; fi

cpu="$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/  */ /g')"
[[ -z "$cpu" ]] && cpu="$(uname -m)"
cores="$(nproc 2>/dev/null || echo 1)"

temp=""
for t in /sys/class/thermal/thermal_zone*/temp; do
	[[ -r "$t" ]] || continue
	v="$(cat "$t" 2>/dev/null)"
	if [[ -n "$v" ]]; then temp="$((v / 1000))C"; break; fi
done

gpu=""
if have lspci; then gpu="$(lspci 2>/dev/null | awk -F': ' '/VGA|3D controller/{print $2; exit}')"; fi

mem_total="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
mem_avail="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
mem_used=$(((mem_total - mem_avail) / 1024))
mem_total=$((mem_total / 1024))

battery=""; bstate=""
for b in /sys/class/power_supply/BAT*; do
	[[ -d "$b" ]] || continue
	battery="$(cat "$b/capacity" 2>/dev/null)"
	bstate="$(cat "$b/status" 2>/dev/null)"
	break
done

res=""
if have swaymsg; then
	res="$(swaymsg -t get_outputs 2>/dev/null | awk -F'"' '/current_mode/{print $4; exit}')"
fi

RULE="--------------------------------------------"

# The script must also work when a caller has "set -e" enabled
# (e.g. started from a shell with errexit), so no bare test is used as a
# statement and every optional row is guarded by an if-block.

# plain (already coloured) info lines
info=()
info+=("${bold}${green}$(whoami)@$(hostname -s)${reset}")
info+=("${blue}${RULE}${reset}")
info+=("${blue}Distro${reset}:     ${fg}${distro}${ver:+ $ver}${reset}")
info+=("${blue}Kernel${reset}:     ${fg}${kernel}${reset}")
info+=("${blue}Uptime${reset}:     ${fg}${uptime}${reset}")
info+=("${blue}DE${reset}:         ${fg}${de}${reset}")
info+=("${blue}Session${reset}:    ${fg}${sess}${reset}")
info+=("${blue}Packages${reset}:   ${fg}${pkgs} (dpkg)${reset}")
info+=("${blue}${RULE}${reset}")
info+=("${blue}CPU${reset}:        ${fg}${cpu}${temp:+ ${yellow}${temp}${reset}}")
[[ -n "${gpu}" ]] && info+=("${blue}GPU${reset}:        ${fg}${gpu}${reset}")
info+=("${blue}Memory${reset}:     ${fg}${mem_used} MiB / ${mem_total} MiB${reset}")
if [[ -n "${res}" ]]; then info+=("${blue}Resolution${reset}: ${fg}${res}${reset}"); fi
info+=("${blue}Cores${reset}:      ${fg}${cores}${reset}")
if [[ -n "${battery}" ]]; then
	info+=("${blue}${RULE}${reset}")
	info+=("${blue}Battery${reset}:    ${fg}${battery}% ${bstate}${reset}")
fi

# Debian swirl (classic ascii logo)
logo=()
while IFS= read -r line; do logo+=("${line}"); done <<'LOGO'
         _,met$$$$$gg.
      ,g$$$$$$$$$$$$$$$P.
    ,g$$P"       """Y$$.".
   ,$$P'              `$$$.
  ',$$P       ,ggs.     `$$b:
  `d$$'     ,$P"'   .    $$$
   $$P      d$'     ,    $$P
   $$:      $$.   -    ,d$$'
   $$;      Y$b._   _,d$P'
   Y$$.    `.`"Y$$$$P"'
   `$$b      "-.__
    `Y$$
     `Y$$.
       `$$b.
         `Y$$b.
            `"Y$b._
                `""""
LOGO

# column widths
n=${#info[@]}
ln=${#logo[@]}
if ((ln > n)); then n=$ln; fi
lw=0
for l in "${logo[@]}"; do
	if ((${#l} > lw)); then lw=${#l}; fi
done
lw=$((lw + 2))

printf '\n'
for ((i = 0; i < n; i++)); do
	l="${logo[i]:-}"
	printf '%s%-*s%s%s\n' "${green}" "${lw}" "${l}" "${reset}" "${info[i]:-}"
done
printf '\n'
MFSCRIPT
	install -m 755 "${tmp}" "${dest}"
	rm -f "${tmp}"
	register_file "${dest}"
	ui_ok "installed /usr/local/bin/mf"
}

write_stats() {
	# Tiny helper for the bar's "launcher" module: prints
	# "NN% MEM · NN% CPU" so the pill shows live figures without waybar
	# having to run a shell pipeline of its own.
	local dest="/usr/local/bin/sway-everforest-stats"
	cat >"${dest}" <<'STATS'
#!/bin/sh
# Memory and CPU usage for the launcher pill.
mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo 2>/dev/null)
# Instantaneous CPU load: sample /proc/stat twice 0.3s apart and use the
# delta. Reading it once gives the average since boot, which barely moves and
# looks like a frozen widget.
cpu=$(
	a=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; printf "%s %s", t, $5}' /proc/stat)
	sleep 0.3
	b=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; printf "%s %s", t, $5}' /proc/stat)
	awk -v a="$a" -v b="$b" 'BEGIN{
		split(a, x, " "); split(b, y, " ");
		dt = y[1] - x[1]; di = y[2] - x[2];
		if (dt <= 0) { print 0; exit }
		printf "%d", (dt - di) * 100 / dt
	}'
)
[ -n "${mem}" ] || mem=0
[ -n "${cpu}" ] || cpu=0
printf '%s%% M  %s%% C\n' "${mem}" "${cpu}"
STATS
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_bar_actions() {
	# Small helpers behind the bar's clickable pills. Each one is a real
	# action: no button is left doing nothing, and no button silently opens a
	# settings dialog when the user expected a menu.

	# --- notifications: toggle do-not-disturb, or dismiss everything ---------
	cat >/usr/local/bin/sway-everforest-notifications <<'NOTIF'
#!/bin/sh
# Left click  : list notification history in a menu
# Right click : toggle do-not-disturb
#   history     show past notifications (wofi list, click to dismiss one)
#   toggle      switch do-not-disturb on/off
#   clear       wipe the popups AND the stored history
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sway-everforest-dnd"
history="${XDG_STATE_HOME:-$HOME/.local/state}/sway-everforest/notifications.log"

dnd_on() { [ -e "${state}" ]; }

notify() {
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t 1500 "Notifications" "$1"
	exit 0
}

show_history() {
	# Show each notification as one truncated line "time  summary — body…";
	# picking a line opens the full text in a second menu.
	#
	# The source is notifications.log, written by sway-everforest-notify-log.
	# mako cannot supply this: makoctl exposes only summary, app name and
	# urgency, so a menu built from it can never show what a notification said.
	# The logger watches the D-Bus Notify call, which does carry the body.
	#
	# Record format, one line each:
	#     <epoch>\t<app>\t<summary>\t<body, newlines as literal \n>
	mkdir -p "$(dirname "${history}")" 2>/dev/null

	if [ ! -s "${history}" ]; then
		notify "No notifications yet"
	fi

	command -v wofi >/dev/null 2>&1 || exit 0

	# Index file: one line per rendered row, holding the 1-based record number
	# so a click can be mapped back to the full record. wofi returns only the
	# text of the chosen row, so the row and the record must stay in step.
	rows=$(mktemp 2>/dev/null) || exit 0
	index=$(mktemp 2>/dev/null) || { rm -f "${rows}"; exit 0; }
	# shellcheck disable=SC2064
	trap 'rm -f "${rows}" "${index}"' EXIT INT TERM

	# Newest first, capped so the menu stays usable.
	tac "${history}" 2>/dev/null | head -100 | awk -F'\t' '
		function flatten(s) {
			# The logger escaped newlines as the two characters \ n.
			gsub(/\\n/, " ", s)
			gsub(/\\t/, " ", s)
			return s
		}
		BEGIN { n = 0 }
		{
			n++
			ts = $1; app = $2; sum = $3; body = $4
			when = strftime("%H:%M", ts)
			if (when == "") when = "--:--"
			title = sum
			if (title == "") title = app
			text = flatten(body)
			line = title
			if (text != "" && text != title) line = title " — " text
			if (length(line) > 108) line = substr(line, 1, 105) "..."
			printf "%s  %s\n", when, line
			# Remember which record this row belongs to, and keep the raw text.
			printf "%d\n", n
		}
	' >"${rows}" 2>/dev/null

	# Keep the records in the same order as the rows for lookup by number.
	records=$(mktemp 2>/dev/null) || { rm -f "${rows}" "${index}"; exit 0; }
	tac "${history}" 2>/dev/null | head -100 >"${records}"

	[ -s "${rows}" ] || { notify "No notifications yet"; }

	choice=$(wofi --dmenu --prompt "Notifications" --width 760 --height 500 \
		<"${rows}" 2>/dev/null)
	[ -n "${choice}" ] || exit 0

	# Which row was picked? Match by exact text; duplicates resolve to the
	# first, which is fine because identical rows are interchangeable.
	lineno=$(awk -v want="${choice}" '$0 == want { print NR; exit }' "${rows}" 2>/dev/null)
	[ -n "${lineno}" ] || exit 0

	record=$(sed -n "${lineno}p" "${records}" 2>/dev/null)
	[ -n "${record}" ] || exit 0

	# Split the record for the detail view.
	r_ts=$(printf '%s' "${record}" | cut -f1)
	r_app=$(printf '%s' "${record}" | cut -f2)
	r_sum=$(printf '%s' "${record}" | cut -f3)
	r_body=$(printf '%s' "${record}" | cut -f4- | sed 's/\\n/\n/g')

	when=$(date -d "@${r_ts}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${r_ts}")

	# Detail view. wofi --dmenu cannot wrap text, so the body is folded to a
	# readable width first; that is what makes long notifications legible
	# instead of a single clipped line.
	detail=$(mktemp 2>/dev/null) || exit 0
	{
		printf '%s\n' "${r_sum}"
		printf '\n'
		printf '应用  %s\n' "${r_app}"
		printf '时间  %s\n' "${when}"
		printf '\n'
		if [ -n "${r_body}" ]; then
			printf '%s\n' "${r_body}" | fold -s -w 86
		else
			printf '(无正文)\n'
		fi
	} >"${detail}"

	wofi --dmenu --prompt "详情" --width 760 --height 500 \
		--insensitive <"${detail}" >/dev/null 2>&1
	rm -f "${detail}" "${records}"

	# Offer to clear, as before.
	act=$(printf '清空全部历史\n取消\n' |
		wofi --dmenu --prompt "操作" --width 320 --height 160 2>/dev/null)
	if [ "${act}" = "清空全部历史" ]; then
		makoctl dismiss --all >/dev/null 2>&1
		: >"${history}" 2>/dev/null
	fi
	exit 0
}

set_dnd() {
	if dnd_on; then
		rm -f "${state}"
		command -v makoctl >/dev/null 2>&1 && makoctl set-mode default >/dev/null 2>&1
	else
		: >"${state}"
		command -v makoctl >/dev/null 2>&1 && makoctl set-mode do-not-disturb >/dev/null 2>&1
	fi
}

case "${1:-history}" in
	history|list) show_history ;;
	toggle)
		set_dnd
		if dnd_on; then notify "Do not disturb on"; else notify "Do not disturb off"; fi
		;;
	dismiss|clear)
		# Middle click on the bell means "wipe notifications", not just "hide
		# what is on screen": clear the popups AND the stored history, otherwise
		# the list still shows everything afterwards. Same contract as the X11
		# helper, which calls dunstctl close-all + history-clear.
		command -v makoctl >/dev/null 2>&1 && makoctl dismiss --all >/dev/null 2>&1
		: >"${history}" 2>/dev/null
		exit 0
		;;
	*) show_history ;;
esac
NOTIF
	chmod 755 /usr/local/bin/sway-everforest-notifications
	register_file /usr/local/bin/sway-everforest-notifications

	# --- clock: a calendar popup ---------------------------------------------
	cat >/usr/local/bin/sway-everforest-calendar <<'CAL'
#!/bin/sh
# Clock actions, same contract as the X11 rice's calendar helper:
#
#   (default)   show the date as a desktop notification
#   terminal    open this month's calendar in a terminal window
#
# The X11 version's left click is a notification and its right click is the
# month grid. Reproducing both here is what makes the clock's two buttons do
# different things instead of the same one.
export LC_ALL=C

say() {
	command -v notify-send >/dev/null 2>&1 || return 1
	notify-send -a Everforest -t "${2:-5000}" "$1" "$3"
}

if [ "${1:-notice}" != "terminal" ]; then
	# Left click: a compact notification with weekday, date and ISO week.
	day=$(date '+%A')
	rest=$(date '+%d %B %Y')
	week=$(date '+%V')
	say "Calendar - ${day}" 6000 "${rest}
week ${week}"
	exit 0
fi

# Right click: the full month grid in a terminal.
term="${TERMINAL:-foot}"
command -v "${term}" >/dev/null 2>&1 || term=alacritty
command -v "${term}" >/dev/null 2>&1 || term=xterm
if ! command -v "${term}" >/dev/null 2>&1; then
	say "Calendar" 4000 "No terminal emulator found"
	exit 1
fi

cmd='python3 -c "
import calendar, datetime
t = datetime.date.today()
print(calendar.TextCalendar(calendar.MONDAY).formatmonth(t.year, t.month))
print(t.strftime(\"%A %d %B %Y\"), \" week\", t.strftime(\"%V\"))
"; printf "\nPress Enter to close. "; read -r _'

"${term}" -T "Calendar" -e sh -c "${cmd}" >/dev/null 2>&1 &
exit 0
CAL
	chmod 755 /usr/local/bin/sway-everforest-calendar
	register_file /usr/local/bin/sway-everforest-calendar

	# --- sysinfo pill: memory + a live CPU sparkline -------------------------
	#
	# Matches the C bar's pill as closely as Waybar allows. The C bar draws a
	# real 46x20 cairo polyline; Waybar's `custom` module can only emit text,
	# so the same shape is built from Unicode block glyphs.
	#
	# "Same shape" means the same *view* of the data, not a character for
	# every pixel: 20 samples of the same 250ms CPU reading the C bar uses,
	# quantised to the eight block levels, drawn newest-on-the-right. The
	# braille/block ladder is what every terminal sparkline uses, and at this
	# size it reads as a line rather than as bars.
	#
	# State lives in a file under XDG_RUNTIME_DIR so the pill keeps its
	# history between Waybar's interval ticks: Waybar runs `exec` afresh each
	# time, so the script has to remember the previous samples itself.
	# --- memory pill ---------------------------------------------------------
	cat >/usr/local/bin/sway-everforest-memory <<'MEM'
#!/bin/sh
# Memory percentage for the Waybar pill. Reads /proc/meminfo directly so no
# process is spawned beyond the script itself.
export LC_ALL=C
if [ -r /proc/meminfo ]; then
	total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
	avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
	if [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
		printf '%s%%\n' "$(( (total - avail) * 100 / total ))"
		exit 0
	fi
fi
printf -- '--%%\n'
MEM
	chmod 755 /usr/local/bin/sway-everforest-memory
	register_file /usr/local/bin/sway-everforest-memory

	# --- CPU sparkline -------------------------------------------------------
	#
	# Matches the C bar's CPU line as closely as Waybar allows.
	#
	# The C bar draws a real 46x20 cairo polyline, repainted at 15Hz over the
	# last 5 seconds of load (20 samples x 250ms). Waybar's `custom` module can
	# only emit text, so the same shape is rebuilt from Unicode block glyphs,
	# newest on the right, one glyph per sample.
	#
	# Because Waybar re-execs the module on its own interval, the sample
	# history is kept in $XDG_RUNTIME_DIR: each run appends one CPU reading and
	# prints the last 20. The window is therefore 20 seconds rather than 5 -
	# coarser in time, the same shape. Running the module faster than 1s would
	# mean spawning a process several times a second, which costs more than the
	# graph is worth.
	cat >/usr/local/bin/sway-everforest-cpugraph <<'CPUG'
#!/bin/sh
# Print a CPU sparkline for Waybar, drawn as braille dots.
#
# The C bar strokes a 1.6px cairo polyline across 90x14px. Block glyphs
# (U+2581..) could not reproduce that: each block fills a whole character cell,
# so the line came out 3px thick and read as a solid bar rather than a line.
#
# Braille (U+2800..U+28FF) is a 2x4 dot matrix per cell, so one character
# carries eight independently addressable points. That is fine enough to draw a
# one-dot-thick line, and it is still plain text - no images, no extra process.
#
# Layout: 13 cells wide (26 dot columns) by 4 dot rows. Measured at 9px per
# cell that is ~30px of line, one third of the 90px it used to occupy.
export LC_ALL=C

state_dir="${XDG_RUNTIME_DIR:-/tmp}"
hist="${state_dir}/sway-everforest-cpu.hist"
POINTS=26          # dot columns; two per braille cell
COLS=13            # braille characters (one third of the 90px version)
ROWS=12           # dot rows total (3 cells x 4)

# ---- one CPU sample -------------------------------------------------------
now=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null)
tot=${now% *}
idle=${now#* }

ptot=0; pidle=0
if [ -r "${hist}.prev" ]; then
	read -r ptot pidle <"${hist}.prev" 2>/dev/null || { ptot=0; pidle=0; }
fi
printf '%s %s\n' "$tot" "$idle" >"${hist}.prev" 2>/dev/null

pct=0
if [ "$ptot" -gt 0 ] 2>/dev/null && [ "$tot" -gt "$ptot" ] 2>/dev/null; then
	dt=$(( tot - ptot ))
	di=$(( idle - pidle ))
	[ "$dt" -gt 0 ] && pct=$(( (dt - di) * 100 / dt ))
fi
[ "$pct" -gt 100 ] && pct=100

# ---- history --------------------------------------------------------------
if [ -f "$hist" ]; then
	{ cat "$hist"; echo "$pct"; } | tail -n "$POINTS" >"${hist}.tmp" 2>/dev/null &&
		mv "${hist}.tmp" "$hist" 2>/dev/null
else
	printf '%s\n' "$pct" >"$hist" 2>/dev/null
fi

have=$(wc -l <"$hist" 2>/dev/null || echo 0)
pad=$(( POINTS - have ))

# ---- render ---------------------------------------------------------------
# Three rows of braille cells stacked vertically give 12 dot rows. Two rows (8
# levels) were still too coarse: CPU load here sits in a narrow 13-40% band, and
# at 8 levels 13% and 25% both rounded to the same row, so the line stayed flat.
# The C bar maps value straight onto a 20px height (y = h - v/100*(h-2) - 1), so
# 13% and 40% land about 5px apart - 12 levels reproduce that separation.
#
# Each sample is one dot column. The value picks a row from the top (0) and
# every row below it is filled, so the shape reads as a filled area like the
# C bar's 26%-alpha fill under the line.
awk -v pad="$pad" -v cols="$COLS" -v points="$POINTS" '
	BEGIN {
		# Braille bit for (dotcol,dotrow) inside one cell.
		bit[0,0]=1; bit[0,1]=2; bit[0,2]=4; bit[0,3]=64
		bit[1,0]=8; bit[1,1]=16; bit[1,2]=32; bit[1,3]=128
		n = 0
		total_levels = 12
	}
	{
		n++
		if (n == 1) for (i = 0; i < pad; i++) vals[i] = 0
		vals[pad + n - 1] = $1
	}
	END {
		filled = pad + n
		for (i = filled; i < points; i++) vals[i] = 0

		# Row (0 = top of the 8) that the sample reaches.
		# Two passes: the first draws the upper cell row (levels 0-3),
		# the second the lower one (levels 4-7).
		for (half = 0; half < 3; half++) {
			line = ""
			for (c = 0; c < cols; c++) {
				code = 0
				for (k = 0; k < 2; k++) {
					idx = c * 2 + k
					v = vals[idx]
					lvl = total_levels - 1 - int(v * total_levels / 101)
					if (lvl < 0) lvl = 0
					if (lvl > total_levels - 1) lvl = total_levels - 1

					# Dot rows covered by this cell row.
					r0 = half * 4
					for (r = r0; r < r0 + 4; r++)
						if (r >= lvl) code += bit[k, r - r0]
				}
				# U+2800 + code: E2, 0xA0 + code/64, 0x80 + code%64
				b2 = 160 + int(code / 64)
				b3 = 128 + (code % 64)
				line = line sprintf("%c%c%c", 226, b2, b3)
			}
			lines[half] = line
		}

		# Drop leading all-blank rows. A row of U+2800 has no visible ink, and
		# Waybar sizes the module from what it can see, so shipping a blank top
		# row made the whole label collapse and the graph vanish. Printing only
		# from the first non-empty row up keeps the height honest.
		first = 0
		for (i = 0; i < 3; i++) {
			blank = 1
			for (j = 1; j <= length(lines[i]); j++)
				if (substr(lines[i], j, 3) != blankcell) { blank = 0; break }
			if (!blank) { first = i; break }
			first = i + 1
		}
		for (i = first; i < 3; i++) printf "%s\n", lines[i]
	}
' "$hist" 2>/dev/null
CPUG
	chmod 755 /usr/local/bin/sway-everforest-cpugraph
	register_file /usr/local/bin/sway-everforest-cpugraph

	# The old single-pill script is gone; remove it on upgrade.
	rm -f /usr/local/bin/sway-everforest-sysinfo 2>/dev/null

	# --- native Wayland C bar ------------------------------------------------
	#
	# A cairo bar written against wl_shm + wlr-layer-shell, i.e. the X11 bar's
	# drawing code ported to Wayland. It exists because waybar cannot reproduce
	# the C bar's CPU sparkline: waybar's custom modules only emit text, and a
	# character cell cannot express a 1.6px polyline.
	#
	# Compiled here rather than shipped as a binary, so it links against the
	# libwayland/cairo/pango the target actually has.
	bar_wl_build() {
		local src="${ASSET_DIR}/bar-sway"
		local build=/usr/local/src/i3-everforest-bar-wl

		[[ -d "${src}" ]] || { ui_err "the C bar payload is missing"; return 1; }
		if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
			ui_dim "would build the native Wayland bar"
			return 0
		fi

		# Build deps: the protocol scanner and the library headers.
		if ! command -v wayland-scanner >/dev/null 2>&1 ||
		   ! pkg-config --exists wayland-client cairo pangocairo xkbcommon 2>/dev/null; then
			ui_step "installing the Wayland build dependencies"
			apt_install "Wayland dev" wayland-protocols libwayland-dev \
				libxkbcommon-dev libcairo2-dev libpango1.0-dev \
				|| { ui_err "the C bar cannot be built without them"; return 1; }
		fi

		rm -rf "${build}"
		mkdir -p "${build}"
		cp -a "${src}/." "${build}/"

		# The protocol code is generated, not checked in, so it always matches
		# the scanner version on this machine.
		(cd "${build}" && \
		 wayland-scanner client-header \
			/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
			proto/xdg-shell-client.h && \
		 wayland-scanner private-code \
			/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
			proto/xdg-shell-protocol.c) >>"${LOG_FILE}" 2>&1 \
			|| ui_err "could not regenerate the xdg-shell protocol code"

		if (cd "${build}" && make clean >/dev/null 2>&1; make) >>"${LOG_FILE}" 2>&1; then
			install -m 755 "${build}/i3-everforest-bar-wl" /usr/local/bin/i3-everforest-bar-wl
			register_file /usr/local/bin/i3-everforest-bar-wl
			ui_ok "built /usr/local/bin/i3-everforest-bar-wl"
			return 0
		fi
		# Hard failure: the bar is the only one this rice installs, so a build
		# that does not produce the binary has to stop the install rather than
		# leave a desktop with no bar at all.
		ui_err "the C bar failed to build (see ${LOG_FILE})"
		return 1
	}
	bar_wl_build || die "the bar could not be built; aborting so the session is not left without one"

	# --- power menu ----------------------------------------------------------
	#
	# The i3 rice paints its own full-screen GTK grid instead of using wlogout,
	# because wlogout is a Wayland program and the i3 session is X11. Here the
	# situation is reversed: this script would work under Wayland, but the i3
	# layout is what the bar's power button is supposed to match, so the same
	# GTK grid is reused with the session commands swapped for their Wayland
	# equivalents (swaymsg exit, swaylock).
	cat >/usr/local/bin/sway-everforest-powermenu-ui <<'PWRUI'
#!/usr/bin/env python3
"""Full-screen power menu (wlogout look) for Sway/Wayland."""
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

SCRIM = (0.055, 0.067, 0.071, 0.72)   # translucent: picom blurs it

# Nerd Font glyphs, the same set the bar uses:
#   U+F023 lock  U+F2F5 sign-out  U+F186 moon  U+F021 refresh  U+F011 power
ACTIONS = [
    ("Lock", "\uf023", ["swaylock", "-f", "-c", "1e2326"]),
    ("Log out", "\uf2f5", ["swaymsg", "exit"]),
    ("Suspend", "\uf186", ["sh", "-c",
                            "swaylock -f -c 1e2326; "
                            "sleep 1; systemctl suspend"]),
    ("Reboot", "\uf021", ["systemctl", "reboot"]),
    ("Shutdown", "\uf011", ["systemctl", "poweroff"]),
]

# A GtkButton is used for each tile: it lays its child out correctly and honours
# min-width/min-height. Selectors are written so the icon rule cannot be beaten
# by a generic `.tile label` rule (equal specificity was collapsing the glyph to
# the label's 14px).
CSS = b"""
.tile {
  background-color: rgba(30, 35, 38, 0.88);
  background-image: none;
  border: 1px solid #3a4044;
  border-radius: 10px;
  padding: 26px 8px 18px 8px;
  min-width: 150px;
  min-height: 168px;
  box-shadow: none;
  text-shadow: none;
  outline-style: none;
}
.tile:hover {
  background-color: #2f3336;
  border-color: #b9ff66;
}
.tile .tile-icon {
  color: #d3c6aa;
  font-size: 52px;
  min-height: 64px;
}
.tile:hover .tile-icon {
  color: #b9ff66;
}
.tile .tile-text {
  color: #d3c6aa;
  font-size: 14px;
  font-weight: 700;
  margin-top: 12px;
}
.tile:hover .tile-text {
  color: #fffbef;
}
"""


def spawn(cmd):
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def main():
    win = Gtk.Window()
    win.set_decorated(False)
    win.set_skip_taskbar_hint(True)
    win.set_skip_pager_hint(True)
    win.set_keep_above(True)
    # Size to the whole output instead of calling fullscreen().
    #
    # fullscreen() makes GTK hand the surface to the compositor as a fullscreen
    # toplevel, and scenefx then composites it without alpha: the translucent
    # scrim came out as a flat dark rectangle, hiding the very backdrop the
    # blur was supposed to frost. A floating window of output size keeps the
    # ARGB path intact, so the scrim blends with the windows below.
    geom = win.get_screen().get_monitor_geometry(0)
    if geom is not None:
        win.set_default_size(geom.width, geom.height)
        win.move(geom.x, geom.y)

    screen = win.get_screen()
    visual = screen.get_rgba_visual()
    if visual is not None and screen.is_composited():
        win.set_visual(visual)
    win.set_app_paintable(True)


    prov = Gtk.CssProvider()
    prov.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        screen, prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    scrim = Gtk.EventBox()
    scrim.override_background_color(Gtk.StateFlags.NORMAL, Gdk.RGBA(*SCRIM))
    win.add(scrim)

    grid = Gtk.Grid()
    grid.set_row_spacing(22)
    grid.set_column_spacing(22)
    grid.set_halign(Gtk.Align.CENTER)
    grid.set_valign(Gtk.Align.CENTER)
    scrim.add(grid)

    def on_click(cmd):
        def handler(_b):
            spawn(cmd)
            Gtk.main_quit()
        return handler

    for i, (text, glyph, cmd) in enumerate(ACTIONS):
        tile = Gtk.Button()
        tile.get_style_context().add_class("tile")
        tile.set_relief(Gtk.ReliefStyle.NONE)
        tile.set_can_focus(False)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        icon = Gtk.Label(label=glyph)
        icon.get_style_context().add_class("tile-icon")
        icon.set_xalign(0.5)
        label = Gtk.Label(label=text)
        label.get_style_context().add_class("tile-text")
        label.set_xalign(0.5)
        inner.pack_start(icon, True, True, 0)
        inner.pack_start(label, False, False, 0)
        tile.add(inner)

        tile.connect("clicked", on_click(cmd))
        grid.attach(tile, i, 0, 1, 1)

    def on_key(_w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        return False

    win.connect("key-press-event", on_key)
    def _cleanup(*_a):
        try:
            os.unlink(lock)
        except Exception:
            pass
        Gtk.main_quit()

    win.connect("destroy", _cleanup)
    GLib.timeout_add_seconds(60, lambda: (Gtk.main_quit(), False)[1])
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PWRUI
	chmod 755 /usr/local/bin/sway-everforest-powermenu-ui
	register_file /usr/local/bin/sway-everforest-powermenu-ui

	cat >/usr/local/bin/sway-everforest-powermenu <<'PWR'
#!/bin/sh
# Power menu for the bar's red button and for Mod+Shift+E.
export LC_ALL=C
exec /usr/local/bin/sway-everforest-powermenu-ui
PWR
	chmod 755 /usr/local/bin/sway-everforest-powermenu
	register_file /usr/local/bin/sway-everforest-powermenu

	# --- system monitor: what clicking the CPU pill opens --------------------
	cat >/usr/local/bin/sway-everforest-sysinfo-monitor <<'MON'
#!/bin/sh
# Open a live view of CPU, memory and disk.
term="${TERMINAL:-foot}"
command -v foot >/dev/null 2>&1 || term=alacritty
command -v "${term}" >/dev/null 2>&1 || term=xterm
if command -v btop >/dev/null 2>&1; then
	exec "${term}" -e btop
fi
exec "${term}" -e sh -c 'while :; do clear; echo "CPU / memory"; echo; top -bn1 | head -12; sleep 2; done'
MON
	chmod 755 /usr/local/bin/sway-everforest-sysinfo-monitor
	register_file /usr/local/bin/sway-everforest-sysinfo-monitor

	# --- wifi: scan and connect ----------------------------------------------
	cat >/usr/local/bin/sway-everforest-wifi <<'WIFI'
#!/bin/sh
# WiFi control for the bar, driven entirely by NetworkManager.
#
#   (no args)   left click:  pick a network and join it
#   config      right click: connection details (state, IP, signal, actions)
#
# Same contract as the X11 rice: the two buttons do different things. Every
# failure mode says something, because a click that silently does nothing is
# indistinguishable from a broken button.
export LC_ALL=C
PATH="/usr/sbin:/sbin:$PATH"

say() {
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t "${2:-4000}" "WiFi" "$1"
	exit "${3:-0}"
}

have_nm() {
	command -v nmcli >/dev/null 2>&1 || return 1
	systemctl is-active --quiet NetworkManager 2>/dev/null
}

wifi_dev() {
	nmcli -t -f DEVICE,TYPE device 2>/dev/null |
		awk -F: '$2=="wifi"{print $1; exit}'
}

# Fall back to Ethernet when there is no wireless adaptor at all. A desktop
# with only a cable should still get a network menu, and the bar draws an
# Ethernet icon in that case, so the menu has to match.
ethernet_dev() {
	nmcli -t -f DEVICE,TYPE device 2>/dev/null |
		awk -F: '$2=="ethernet"{print $1; exit}'
}

show_config() {
	have_nm || say "NetworkManager is not running"

	dev=$(wifi_dev)
	# Ethernet-only machine: detail the wired link rather than refusing.
	[ -n "$dev" ] || dev=$(ethernet_dev)
	[ -n "$dev" ] || say "No network adaptor detected"

	fields=$(nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR,\
IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$dev" 2>/dev/null)

	get() {
		printf '%s\n' "$fields" | grep -E "^$1(\[[0-9]+\])?:" |
			cut -d: -f2- | head -1
	}
	get_all() {
		printf '%s\n' "$fields" | grep -E "^$1(\[[0-9]+\])?:" |
			cut -d: -f2- | sed '/^$/d' | paste -sd' ' -
	}

	state=$(get GENERAL.STATE)
	conn=$(get GENERAL.CONNECTION)
	mac=$(get GENERAL.HWADDR)
	ip=$(get IP4.ADDRESS | cut -d/ -f1)
	gw=$(get IP4.GATEWAY)
	dns=$(get_all IP4.DNS)

	# Same cache-first read as the list: this runs while the menu opens, so a
	# live scan here would reintroduce the delay the cache exists to remove.
	wcache="${XDG_RUNTIME_DIR:-/tmp}/sway-everforest-wifi.cache"
	link=""
	[ -f "${wcache}" ] && link=$(awk -F: '$1=="*"{print; exit}' "${wcache}" 2>/dev/null)
	[ -n "${link}" ] || link=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null |
		awk -F: '$1=="*"{print; exit}')
	ssid=$(printf '%s' "$link" | cut -d: -f2)
	sig=$(printf '%s' "$link" | cut -d: -f3)
	chan=$(iw dev "$dev" info 2>/dev/null | awk '/channel/{print $2; exit}')
	rate=$(iw dev "$dev" link 2>/dev/null | awk '/bitrate/{print $2, $3; exit}')
	bssid=$(iw dev "$dev" link 2>/dev/null | awk '/Connected to/{print $3; exit}')

	info="Interface : ${dev}
State     : ${state:-unknown}
Network   : ${ssid:-none}
BSSID     : ${bssid:-n/a}
MAC       : ${mac:-n/a}
IP        : ${ip:-none}
Gateway   : ${gw:-none}
DNS       : ${dns:-none}
Signal    : ${sig:-n/a}%
Channel   : ${chan:-n/a}
Rate      : ${rate:-n/a}"

	menu="Reconnect
Disconnect
Forget this network
Open advanced editor
Copy IP to clipboard
Close"

	# wofi has no -mesg; the state block goes into the prompt line instead.
	choice=$(printf '%s\n' "${menu}" |
		wofi --dmenu --prompt "WiFi: ${ssid:-$dev} | IP ${ip:-none} | ${sig:-?}%" \
			--width 540 --height 430 2>/dev/null)
	[ -n "$choice" ] || exit 0

	case "$choice" in
	Reconnect)
		[ -n "$conn" ] && [ "$conn" != "--" ] || exit 0
		nmcli connection down id "$conn" >/dev/null 2>&1
		nmcli connection up id "$conn" >/dev/null 2>&1 &&
			say "Reconnected to $conn" 3000 0
		say "Could not reconnect $conn" 4000 1
		;;
	Disconnect)
		nmcli device disconnect "$dev" >/dev/null 2>&1 &&
			say "Disconnected" 3000 0
		say "Could not disconnect" 4000 1
		;;
	Forget*)
		[ -n "$conn" ] && [ "$conn" != "--" ] || exit 0
		nmcli connection delete id "$conn" >/dev/null 2>&1 &&
			say "Forgot $conn" 3000 0
		say "Could not forget $conn" 4000 1
		;;
	Open\ advanced*)
		if command -v nm-connection-editor >/dev/null 2>&1; then
			nm-connection-editor >/dev/null 2>&1 &
		elif command -v nmtui >/dev/null 2>&1; then
			${TERMINAL:-foot} -e nmtui >/dev/null 2>&1 &
		else
			say "No connection editor installed" 4000 1
		fi
		exit 0
		;;
	Copy\ IP*)
		if [ -n "$ip" ] && command -v wl-copy >/dev/null 2>&1; then
			printf '%s' "$ip" | wl-copy 2>/dev/null
			say "Copied $ip" 2500 0
		fi
		say "No IP to copy" 3000 1
		;;
	esac
	exit 0
}

# Menu for a machine with no wireless adaptor.
#
# A wired link cannot be "joined" like a wifi network - the plug either carries
# a link or it does not - so the useful actions are status, connect/disconnect
# and the connection editor.
show_wired_menu() {
	dev=$(ethernet_dev)
	if [ -z "$dev" ]; then
		say "No network adaptor detected"
	fi

	state=$(nmcli -t -f GENERAL.STATE device show "$dev" 2>/dev/null |
		cut -d: -f2- | head -1)
	conn=$(nmcli -t -f GENERAL.CONNECTION device show "$dev" 2>/dev/null |
		cut -d: -f2- | head -1)
	ip=$(nmcli -t -f IP4.ADDRESS device show "$dev" 2>/dev/null |
		cut -d: -f3 | head -1)

	if printf '%s' "$state" | grep -q "connected"; then
		label="Ethernet  $dev   ${ip:-no address}"
	else
		label="Ethernet  $dev   (disconnected)"
	fi

	choice=$(printf '%s\n' \
		"$label" \
		"Connect" \
		"Disconnect" \
		"Open advanced editor" \
		"Copy IP to clipboard" \
		"Close" |
		wofi --dmenu --prompt "Network: ${dev} | ${ip:-no address}" \
			--width 520 --height 300 2>/dev/null)

	[ -n "$choice" ] || exit 0
	case "$choice" in
	Connect)
		[ -n "$conn" ] && nmcli connection up "$conn" >/dev/null 2>&1
		nmcli device connect "$dev" >/dev/null 2>&1 &&
			say "Connected $dev" 2500 0
		say "Could not bring $dev up" 3500 1
		;;
	Disconnect)
		nmcli device disconnect "$dev" >/dev/null 2>&1 &&
			say "Disconnected $dev" 2500 0
		say "Could not disconnect $dev" 3500 1
		;;
	Open*)
		if command -v nm-connection-editor >/dev/null 2>&1; then
			nm-connection-editor >/dev/null 2>&1 &
		elif command -v nmtui >/dev/null 2>&1; then
			${TERMINAL:-foot} -e nmtui >/dev/null 2>&1 &
		else
			say "No connection editor installed" 3000 1
		fi
		exit 0
		;;
	Copy*)
		if [ -n "$ip" ] && command -v wl-copy >/dev/null 2>&1; then
			printf '%s' "$ip" | wl-copy 2>/dev/null
			say "Copied $ip" 2000 0
		fi
		say "No IP to copy" 2500 1
		;;
	esac
	exit 0
}

show_list() {

command -v nmcli >/dev/null 2>&1 || say "NetworkManager is not installed"

# Is there a wireless adaptor at all? Without one nothing can be scanned, and
# saying so is more useful than an empty menu.
has_wifi_dev() {
	nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{found=1} END{exit !found}'
}

if ! has_wifi_dev; then
	# Some adaptors are rfkill-blocked and do not show up until unblocked.
	if command -v rfkill >/dev/null 2>&1 && rfkill list wifi 2>/dev/null | grep -q "blocked: yes"; then
		rfkill unblock wifi >/dev/null 2>&1
		sleep 2
	fi
	if ! has_wifi_dev; then
		# No wireless adaptor even after an rfkill unblock: fall back to the
		# wired link. The bar shows an Ethernet icon in this case.
		show_wired_menu
		exit 0
	fi
fi

# Make sure the radio is on, then wait for the adaptor to come up.
nmcli radio wifi on >/dev/null 2>&1
attempt=0
while [ "${attempt}" -lt 6 ]; do
	nmcli -t -f WIFI general 2>/dev/null | grep -q '^enabled' && break
	attempt=$((attempt + 1))
	sleep 1
done

# Scan on demand, showing progress while the radio works.
#
# The previous version relied on a background refresher that rescanned every
# 20 seconds. That removed the wait, but kept the radio busy forever even when
# nobody opened the list. Scanning only on click is cheaper and just as fast to
# feel, as long as the user gets feedback immediately.
#
# wofi cannot stream: it renders only after stdin closes, and it has no
# equivalent of rofi's live re-read. So the feedback is a notification, and the
# menu is built once the scan has landed.
cache="${XDG_RUNTIME_DIR:-/tmp}/sway-everforest-wifi.cache"
list=""

scan_and_notify() {
	# A background notification, not a blocking one: closing it early must not
	# cancel the scan, so it is fired and forgotten.
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t 3000 "WiFi" "Scanning for networks..." \
			>/dev/null 2>&1 &
	nmcli device wifi rescan >/dev/null 2>&1
	attempt=0
	while [ "$attempt" -lt 12 ]; do
		out=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null)
		[ -n "$out" ] && break
		attempt=$((attempt + 1))
		sleep 0.5
	done
	printf '%s\n' "$out" >"$cache"
	printf '%s\n' "$out"
}

list=$(scan_and_notify | awk -F: 'NF>=4 && $2!="" {print $2}' | sed '/^$/d' | sort -u)

if [ -z "${list}" ]; then
	if ! nmcli -t -f WIFI general 2>/dev/null | grep -q '^enabled'; then
		say "WiFi could not be enabled - check the hardware switch"
	fi
	say "No networks found - move closer or try again"
fi

ssid=$(printf '%s\n' "${list}" |
	wofi --dmenu --prompt "WiFi" --width 420 --height 420 --insensitive 2>/dev/null)

[ -n "${ssid}" ] || exit 0
[ "${ssid}" = "--insensitive" ] && exit 0

# Reuse a saved profile when there is one, otherwise connect fresh.
if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "${ssid}"; then
	nmcli connection up "${ssid}" >/dev/null 2>&1 &&
		say "Connected to ${ssid}" 2000
fi
if nmcli device wifi connect "${ssid}" >/dev/null 2>&1; then
	say "Connected to ${ssid}" 2000
fi
# A password-protected network needs interactive input; hand it to the editor.
nmcli --ask device wifi connect "${ssid}" </dev/null >/dev/null 2>&1 &&
	say "Connected to ${ssid}" 2000
nm-connection-editor >/dev/null 2>&1 &
say "Could not connect to ${ssid} - opening the connection editor"
}

case "${1:-list}" in
config) show_config ;;
*) show_list ;;
esac
WIFI
	chmod 755 /usr/local/bin/sway-everforest-wifi
	register_file /usr/local/bin/sway-everforest-wifi


	# --- input method: toggle whichever framework is actually running --------
	cat >/usr/local/bin/sway-everforest-ime <<'IME'
#!/bin/sh
# Input method control for the bar. Same contract as the X11 rice:
#
#   toggle   left click: switch between the configured input methods
#   config   right click: state, current IM, hotkey, and quick actions
export LC_ALL=C

say() {
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t "${2:-2500}" "Input method" "$1"
	exit "${3:-0}"
}

have_fcitx() {
	command -v fcitx5-remote >/dev/null 2>&1 && pgrep -x fcitx5 >/dev/null 2>&1
}

pretty() {
	case "$1" in
	""|keyboard-us) printf 'English' ;;
	pinyin) printf 'Pinyin' ;;
	*) printf '%s' "$1" ;;
	esac
}

do_toggle() {
	if have_fcitx; then
		fcitx5-remote -t >/dev/null 2>&1 && exit 0
	fi
	if command -v ibus >/dev/null 2>&1 && pgrep -x ibus-daemon >/dev/null 2>&1; then
		ibus engine "$(ibus engine | grep -q xkb && echo pinyin || echo xkb:us::eng)" >/dev/null 2>&1 && exit 0
	fi
	# No framework: bind the key to the system layout switcher instead.
	if command -v swaymsg >/dev/null 2>&1; then
		swaymsg 'input type:keyboard xkb_switch_layout next' >/dev/null 2>&1 || true
	fi
	if command -v fcitx5 >/dev/null 2>&1 || command -v ibus >/dev/null 2>&1; then
		say "No IM daemon is running"
	else
		say "No input method installed"
	fi
}

do_config() {
	# Framework, state and the current input method.
	if have_fcitx; then
		fw="fcitx5"
		state=$(fcitx5-remote 2>/dev/null)
		case "$state" in
		0) state_txt="disabled" ;;
		1) state_txt="inactive (English)" ;;
		2) state_txt="active" ;;
		*) state_txt="unknown" ;;
		esac
		cur=$(fcitx5-remote -n 2>/dev/null)
	else
		fw="none"
		state_txt="no daemon"
		cur=""
	fi

	ims=""
	if [ -f "${HOME}/.config/fcitx5/profile" ]; then
		ims=$(awk -F= '/^Name=/ && !/^Name=Default/ {print $2}' \
			"${HOME}/.config/fcitx5/profile" 2>/dev/null | paste -sd', ' -)
	fi

	# Ctrl+Space is owned by the compositor here (a Wayland client cannot grab
	# keys), so report that rather than fcitx5's own TriggerKeys, which the
	# sway variant deliberately leaves empty.
	hotkey="Ctrl+Space (sway binding)"

	ver=""
	have_fcitx && ver=$(fcitx5 --version 2>/dev/null | head -1)

	info="Framework : ${fw}
State     : ${state_txt}
Current   : $(pretty "${cur:-none}")
Enabled   : ${ims:-none}
Hotkey    : ${hotkey}
Version   : ${ver:-n/a}"

	menu="Switch input method
Restart fcitx5
Open fcitx5 settings
Reload configuration
Close"

	# wofi has no -mesg equivalent, so the state goes into the prompt line.
	choice=$(printf '%s\n' "${menu}" |
		wofi --dmenu --prompt "IME: ${state_txt} / $(pretty "${cur:-none}")" \
			--width 520 --height 380 2>/dev/null)
	[ -n "${choice}" ] || exit 0

	case "${choice}" in
	Switch*)
		fcitx5-remote -t >/dev/null 2>&1 &&
			say "Switched to $(pretty "$(fcitx5-remote -n 2>/dev/null)")" 2000 0
		say "Could not switch" 3000 1
		;;
	Restart*)
		pkill -x fcitx5 2>/dev/null
		sleep 1
		setsid fcitx5 -d --disable virtualkeyboard,emoji,table,spell,kimpanel,quickphrase,unicode,clipboard,notificationitem,fcitx4frontend,ibusfrontend >/dev/null 2>&1 </dev/null &
		sleep 2
		say "fcitx5 restarted" 2000 0
		;;
	Open\ fcitx5*)
		if command -v fcitx5-configtool >/dev/null 2>&1; then
			setsid fcitx5-configtool >/dev/null 2>&1 </dev/null &
			exit 0
		fi
		say "fcitx5-configtool is not installed" 3500 1
		;;
	Reload*)
		fcitx5-remote -r >/dev/null 2>&1 || fcitx5-remote -o >/dev/null 2>&1
		pkill -USR1 -x fcitx5 2>/dev/null
		say "Configuration reloaded" 2000 0
		;;
	esac
	exit 0
}

case "${1:-toggle}" in
config) do_config ;;
*) do_toggle ;;
esac
IME
	chmod 755 /usr/local/bin/sway-everforest-ime
	register_file /usr/local/bin/sway-everforest-ime

	return 0
}

write_sysinfo() {
	# Two helpers for the bar's right-hand pills, matching the reference
	# layout: disk+CPU, and the P/V temperature readout.
	local si="/usr/local/bin/sway-everforest-sysinfo"
	cat >"${si}" <<'SYSINFO'
#!/bin/sh
# Memory and CPU usage for the bar.
mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t>0) printf "%d", (t-a)*100/t; else print 0}' /proc/meminfo)
# Instantaneous CPU load: sample /proc/stat twice 0.3s apart and use the
# delta. Reading it once gives the average since boot, which barely moves and
# looks like a frozen widget.
cpu=$(
	a=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; printf "%s %s", t, $5}' /proc/stat)
	sleep 0.3
	b=$(awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; printf "%s %s", t, $5}' /proc/stat)
	awk -v a="$a" -v b="$b" 'BEGIN{
		split(a, x, " "); split(b, y, " ");
		dt = y[1] - x[1]; di = y[2] - x[2];
		if (dt <= 0) { print 0; exit }
		printf "%d", (dt - di) * 100 / dt
	}'
)
[ -n "$mem" ] || mem=0
[ -n "$cpu" ] || cpu=0
printf '%s %s%%  %s %s%%\n' "" "$mem" "" "$cpu"
SYSINFO
	chmod 755 "${si}"
	register_file "${si}"

	local tp="/usr/local/bin/sway-everforest-temps"
	cat >"${tp}" <<'TEMPS'
#!/bin/sh
# CPU and GPU temperature for the bar.
read_temp() {
	for z in /sys/class/thermal/thermal_zone*/temp; do
		[ -r "$z" ] || continue
		v=$(cat "$z" 2>/dev/null) || continue
		[ -n "$v" ] && { echo $((v / 1000)); return 0; }
	done
	return 1
}
cpu=$(read_temp) || cpu="--"
gpu="--"
if command -v nvidia-smi >/dev/null 2>&1; then
	gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
fi
[ -n "$gpu" ] || gpu="--"
printf ' P/V %s°  %s°\n' "$cpu" "$gpu"
TEMPS
	chmod 755 "${tp}"
	register_file "${tp}"
	return 0
}

write_brightness() {
	# waybar drops the backlight module entirely when there is no
	# /sys/class/backlight, which shifts every control after it. A helper
	# keeps the pill in place and falls back to ddcutil for external screens.
	local dest="/usr/local/bin/sway-everforest-brightness"
	cat >"${dest}" <<'BRIGHT'
#!/bin/sh
# Screen brightness for the waybar pill.
# Order: internal backlight -> external monitor via ddcutil -> dimmed glyph.

set_backlight() {
	if [ -d /sys/class/backlight ] && command -v brightnessctl >/dev/null 2>&1; then
		dev=$(ls /sys/class/backlight | head -1)
		brightnessctl -d "$dev" set "$1" >/dev/null 2>&1 && return 0
	fi
	return 1
}

read_backlight() {
	[ -d /sys/class/backlight ] || return 1
	dev=$(ls /sys/class/backlight | head -1)
	cur=$(cat "/sys/class/backlight/$dev/brightness" 2>/dev/null)
	max=$(cat "/sys/class/backlight/$dev/max_brightness" 2>/dev/null)
	[ -n "$cur" ] && [ -n "$max" ] && [ "$max" -gt 0 ] || return 1
	echo $(( cur * 100 / max ))
}

read_ddc() {
	command -v ddcutil >/dev/null 2>&1 || return 1
	ddcutil getvcp 10 2>/dev/null | sed -n 's/.*current value = *\([0-9]*\).*/\1/p' | head -1
}

case "$1" in
	up)
		set_backlight 5%+ && exit 0
		cur=$(read_ddc) || exit 0
		[ -n "$cur" ] || cur=50
		nxt=$((cur + 10)); [ "$nxt" -gt 100 ] && nxt=100
		ddcutil setvcp 10 "$nxt" >/dev/null 2>&1
		exit 0
		;;
	down)
		set_backlight 5%- && exit 0
		cur=$(read_ddc) || exit 0
		[ -n "$cur" ] || cur=50
		nxt=$((cur - 10)); [ "$nxt" -lt 5 ] && nxt=5
		ddcutil setvcp 10 "$nxt" >/dev/null 2>&1
		exit 0
		;;
esac

p=$(read_backlight) || p=$(read_ddc)
if [ -n "$p" ]; then
	printf '%s \n' "$p"
else
	printf '\n'
fi
BRIGHT
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_volume() {
	# Waybar 0.12's pulseaudio module exposes only {volume}, but the reference
	# shows speaker and microphone together in one pill, so print both here.
	local dest="/usr/local/bin/sway-everforest-volume"
	{
		printf '%s\n' '#!/bin/sh'
		printf '%s\n' '# Speaker and microphone level for the bar volume pill.'
		printf '%s\n' 'command -v pactl >/dev/null 2>&1 || { printf "\\uf026 n/a\\n"; exit 0; }'
		printf '%s\n' ''
		printf '%s\n' 'sink=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o "[0-9]\\+%" | head -1)'
		printf '%s\n' 'src=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o "[0-9]\\+%" | head -1)'
		printf '%s\n' 'smute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -c yes)'
		printf '%s\n' 'rmute=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -c yes)'
		printf '%s\n' '[ -n "$sink" ] || sink="--"'
		printf '%s\n' '[ -n "$src" ] || src="--"'
		printf '%b\n' 'if [ "$smute" -eq 1 ]; then si="\xef\x80\xa6"; else si="\xef\x80\xa7"; fi'
		printf '%b\n' 'if [ "$rmute" -eq 1 ]; then mi="\xef\x84\xb1"; else mi="\xef\x84\xb0"; fi'
		printf '%s\n' 'printf "%s %s  %s %s\\n" "$sink" "$si" "$src" "$mi"'
	} >"${dest}"
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_notify_log() {
	# Mirror notification bodies for the history menu.
	#
	# Runs alongside mako as a pure observer of the D-Bus Notify call. mako
	# itself never exposes a notification's body, so without this the history
	# menu could only ever list titles.
	cat >/usr/local/bin/sway-everforest-notify-log <<'NOTIFYLOG'
#!/usr/bin/env python3
"""Record notification bodies so the history menu can show what they said.

WHY THIS EXISTS

The notification history menu is built from "makoctl history", but mako only
exposes a notification's summary, app name and urgency. The body is accepted
over D-Bus and then dropped, so the menu could never show what a notification
actually said - opening one showed only its title.

The body does exist on the bus: it is the fifth string argument of the
org.freedesktop.Notifications.Notify method call. dbus-monitor can observe
that call without owning the notification name, so this process mirrors what
it sees into a log and leaves mako completely untouched.

DESIGN NOTES

dbus-monitor is used rather than python-dbus message filters because a filter
only sees messages addressed to the calling connection, and mako owns the
name. Monitoring the bus is the supported way to observe another client's
method calls.

Each dbus-monitor record is a "method call" header line followed by the
arguments, printed one per line with strings quoted. A body containing
newlines is printed across several physical lines inside one quoted string,
which is why the parser tracks whether it is inside a string rather than
counting lines.

The log is one record per line, tab separated:

    <epoch>\t<app>\t<summary>\t<body with newlines escaped as \\n>
"""

import os
import subprocess
import sqlite3
import sys
import time

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "sway-everforest",
)
LOG_PATH = os.path.join(STATE_DIR, "notifications.log")

MAX_RECORDS = 500
MAX_BYTES = 512 * 1024

MONITOR_FILTER = (
    "interface='org.freedesktop.Notifications',member='Notify'"
)


def unescape(value: str) -> str:
    """Undo dbus-monitor's C-style escaping of a printed string."""
    out = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            mapping = {
                "n": "\n",
                "t": "\t",
                "r": "\r",
                '"': '"',
                "\\": "\\",
            }
            if nxt in mapping:
                out.append(mapping[nxt])
                i += 2
                continue
            # Unknown escape: keep both characters, do not lose data.
            out.append(ch)
            out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def escape_field(value: str) -> str:
    """Flatten a value onto one log line."""
    return (
        value.replace("\\", "\\\\")
        .replace("\t", " ")
        .replace("\r", " ")
        .replace("\n", "\\n")
    )


class NotifyParser:
    """Turn dbus-monitor's line-oriented output into notification records."""

    STRING_PREFIX = '   string "'

    def __init__(self, emit):
        self.emit = emit
        self.armed = False          # inside a Notify call
        self.strings = []           # completed string arguments
        self.in_string = False
        self.buffer = []            # physical lines of the current string

    def feed(self, line: str) -> None:
        line = line.rstrip("\n")

        if line.startswith("method call") and line.endswith("member=Notify"):
            # A new Notify call: flush the previous one first.
            self._finish_call()
            self.armed = True
            self.strings = []
            self.in_string = False
            self.buffer = []
            return

        # Any other message boundary ends the call's argument list. Without
        # this the strings of an unrelated signal (NameAcquired carries two
        # bus names) were counted as Notify arguments and shifted every field.
        if self.armed and (line.startswith("method call")
                           or line.startswith("signal ")
                           or line.startswith("method return")
                           or line.startswith("error ")):
            self._finish_call()
            return

        if not self.armed:
            return

        if self.in_string:
            # Continuation of a multi-line string.
            if line.endswith('"') and line.count('"') % 2 == 1:
                self.buffer.append(line[:-1])
                self.strings.append(unescape("\n".join(self.buffer)))
                self.buffer = []
                self.in_string = False
                if len(self.strings) == 4:
                    self._finish_call()
            else:
                self.buffer.append(line)
            return

        if line.startswith(self.STRING_PREFIX):
            payload = line[len(self.STRING_PREFIX):]
            if payload.endswith('"') and payload.count('"') % 2 == 1:
                self.strings.append(unescape(payload[:-1]))
                # Notify's four plain strings are app, icon, summary, body. The
                # body is the last thing this tool needs, and waiting for the
                # next message as an end-of-arguments marker would drop the
                # final notification of a session. Emit as soon as it arrives.
                if len(self.strings) == 4:
                    self._finish_call()
            else:
                self.buffer = [payload]
                self.in_string = True
            return

        # A non-string argument after the argument list means the call's
        # arguments are complete; emission happens on the next call header so
        # a multi-line body has a chance to arrive first.

    def _finish_call(self) -> None:
        if not self.armed:
            return
        if self.in_string:
            # Unterminated: keep what we have rather than dropping the record.
            self.strings.append(unescape("\n".join(self.buffer)))
            self.in_string = False
            self.buffer = []

        # Notify(app_name, replaces_id, app_icon, summary, body, actions,
        #        hints, timeout) - the string arguments are therefore:
        #   0 app_name, 1 app_icon, 2 summary, 3 body
        # (replaces_id is a uint32 and actions is a string array whose
        # contents come later, so counting only plain "string" lines gives
        # these four in order.)
        app = self.strings[0] if len(self.strings) > 0 else ""
        summary = self.strings[2] if len(self.strings) > 2 else ""
        body = self.strings[3] if len(self.strings) > 3 else ""

        if summary or body:
            self.emit(app, summary, body)

        self.strings = []
        self.armed = False


def append_record(app: str, summary: str, body: str) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    record = "\t".join(
        [str(int(time.time())), escape_field(app), escape_field(summary),
         escape_field(body)]
    )
    with open(LOG_PATH, "a", encoding="utf-8") as fh:
        fh.write(record + "\n")
    _trim()


def _trim() -> None:
    try:
        size = os.path.getsize(LOG_PATH)
    except OSError:
        return
    if size <= MAX_BYTES:
        # Still check the line count, which can matter for many tiny records.
        with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as fh:
            if sum(1 for _ in fh) <= MAX_RECORDS:
                return
    with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    keep = lines[-MAX_RECORDS:]
    tmp = LOG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(keep)
    os.replace(tmp, LOG_PATH)


def main() -> int:
    env = dict(os.environ)
    # dbus-monitor needs the session bus; a compositor session always has it.
    proc = subprocess.Popen(
        ["dbus-monitor", "--session", MONITOR_FILTER],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=env,
        text=True,
        bufsize=1,
    )
    parser = NotifyParser(append_record)
    assert proc.stdout is not None
    try:
        dbg = os.environ.get("NOTIFY_LOG_DEBUG")
        dbgfh = open(dbg, "a", encoding="utf-8") if dbg else None
        # readline() rather than "for line in stdout": the iterator form reads
        # ahead in blocks, so a live monitor stream would sit in the buffer
        # until the pipe filled and no record would ever be written.
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            if dbgfh:
                dbgfh.write(line)
                dbgfh.flush()
            parser.feed(line)
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
NOTIFYLOG
	chmod 755 /usr/local/bin/sway-everforest-notify-log
	register_file /usr/local/bin/sway-everforest-notify-log
	return 0
}

write_fix_grub() {
	# Repair tool for the kernel GPU driver selection.
	#
	# Shipped as a standalone command rather than folded into the installer
	# because switching radeon -> amdgpu is a boot-level change: if amdgpu
	# cannot drive the panel on a particular machine, the next boot has no
	# display. The user runs it deliberately, from a working session, when the
	# Wayland greeter refuses to start.
	cat >/usr/local/bin/sway-everforest-fix-grub <<'FIXGRUB'
#!/bin/sh
# sway-everforest-fix-grub - repair GPU driver selection in the kernel cmdline.
#
# WHY THIS EXISTS
#
# The installer supports Intel, AMD and NVIDIA graphics out of the box and never
# touches the kernel command line: a boot-level change that goes wrong leaves a
# machine with no display, and that is not a risk an installer should take on the
# user's behalf.
#
# One case does need it. The Wayland greeter runs under weston, and weston 16
# refuses to start without DRM atomic modesetting:
#
#     Error: Kernel DRM KMS does not support DRM_CLIENT_CAP_ATOMIC.
#     fatal: failed to create compositor backend
#
# SDDM has no fallback, so the screen stops at a flashing cursor. On AMD CIK
# hardware (Kaveri and friends) the default radeon driver has no atomic support,
# while amdgpu does, but only with Display Core forced on. This tool performs
# that switch, and can undo it.
#
# USAGE
#
#     sudo sway-everforest-fix-grub              interactive
#     sudo sway-everforest-fix-grub --status     show what is configured
#     sudo sway-everforest-fix-grub --apply      radeon -> amdgpu (with dc=1)
#     sudo sway-everforest-fix-grub --revert     restore the original cmdline
#     sudo sway-everforest-fix-grub --perf on    pin the GPU to high performance
#     sudo sway-everforest-fix-grub --perf off   back to automatic clocks
#
# Every change is idempotent and reversible; the original /etc/default/grub is
# kept verbatim in the backup directory.
set -u

STATE_DIR="/var/lib/sway-everforest"
GRUB_BACKUP="${STATE_DIR}/grub.default.bak"
CLOCK_SERVICE="/etc/systemd/system/amdgpu-performance.service"

# CIK needs both parameters: radeon must let go, amdgpu must take over, and DC
# must be forced on because it is what provides atomic modesetting there.
CIK_PARAMS="radeon.cik_support=0 amdgpu.cik_support=1 amdgpu.dc=1"

say()  { printf '%s\n' "$*"; }
hr()   { printf '%s\n' "----------------------------------------------------------"; }
ok()   { printf '  \033[32m%s\033[0m\n' "$*"; }
warn() { printf '  \033[33m%s\033[0m\n' "$*"; }
err()  { printf '  \033[31m%s\033[0m\n' "$*" >&2; }

need_root() {
	[ "$(id -u)" -eq 0 ] || { err "run this as root (sudo)"; exit 1; }
}

# ---------------------------------------------------------------- probing ---

# Print "vendor:driver:class" for every display controller.
list_gpus() {
	for d in /sys/bus/pci/devices/*; do
		[ -r "$d/class" ] || continue
		read -r cls <"$d/class" || continue
		case "$cls" in
			0x0300*|0x0302*) ;;
			*) continue ;;
		esac
		[ -r "$d/vendor" ] || continue
		read -r vend <"$d/vendor" || continue
		drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
		[ -n "$drv" ] || drv="-"
		printf '%s:%s:%s\n' "$vend" "$drv" "$(basename "$d")"
	done
}

vendor_name() {
	case "$1" in
		0x1002) echo "AMD" ;;
		0x8086) echo "Intel" ;;
		0x10de) echo "NVIDIA" ;;
		*)      echo "unknown($1)" ;;
	esac
}

has_atomic() {
	python3 - /dev/dri/card0 <<'PY' 2>/dev/null
import ctypes, ctypes.util, os, sys
lib = ctypes.util.find_library("drm")
if not lib:
    sys.exit(1)
drm = ctypes.CDLL(lib)
fd = os.open(sys.argv[1], os.O_RDWR)
try:
    # DRM_CLIENT_CAP_ATOMIC = 3
    sys.exit(0 if drm.drmSetClientCap(fd, 3, 1) == 0 else 1)
finally:
    os.close(fd)
PY
}

# The display GPU that the greeter will use: class 0x0300, not the 3D-only one.
primary_gpu() {
	for d in /sys/bus/pci/devices/*; do
		[ -r "$d/class" ] || continue
		read -r cls <"$d/class" || continue
		case "$cls" in 0x0300*) ;; *) continue ;; esac
		[ -r "$d/vendor" ] || continue
		read -r vend <"$d/vendor" || continue
		drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
		printf '%s:%s:%s\n' "$vend" "${drv:--}" "$(basename "$d")"
		return 0
	done
	return 1
}

gpu_clock() {
	f=$(cat /sys/class/drm/card0/device/hwmon/hwmon*/freq1_input 2>/dev/null | head -1)
	[ -n "$f" ] && echo "$((f / 1000000)) MHz" || echo "n/a"
}

gpu_perf_level() {
	cat /sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || echo "n/a"
}

show_status() {
	say "Kernel command line"
	grep -E '^GRUB_CMDLINE_LINUX(_DEFAULT)?=' /etc/default/grub 2>/dev/null | sed 's/^/  /'
	say ""

	say "Running kernel"
	tr ' ' '\n' </proc/cmdline | grep -E 'amdgpu|radeon|nomodeset' | sed 's/^/  /' ||
		say "  (no graphics parameters)"
	say ""

	say "GPUs"
	# Collected first, then printed. list_gpus writes several lines; piping it
	# straight into `grep -q` closes the pipe early and the writer dies with
	# SIGPIPE ("printf: I/O error").
	gpu_list=$(list_gpus)
	if [ -n "$gpu_list" ]; then
		# A PCI slot looks like 0000:00:01.0, so splitting on ":" must keep
		# everything from field 3 onward; -f3 alone would stop at "00".
		primary_slot=$(primary_gpu 2>/dev/null | cut -d: -f3-)
		printf '%s\n' "$gpu_list" | while IFS= read -r line; do
			vend=$(printf '%s' "$line" | cut -d: -f1)
			drv=$(printf '%s' "$line" | cut -d: -f2)
			slot=$(printf '%s' "$line" | cut -d: -f3-)
			mark=""
			[ "$slot" = "$primary_slot" ] && mark="(display)"
			printf '  %-8s %-12s %-14s %s\n' \
				"$(vendor_name "$vend")" "$drv" "$slot" "$mark"
		done
	else
		say "  none detected"
	fi
	say ""

	if has_atomic; then
		ok "DRM atomic modesetting: supported"
	else
		warn "DRM atomic modesetting: NOT supported"
		say "    -> the Wayland greeter cannot start on this GPU"
	fi
	say ""

	say "GPU clocks"
	say "  performance level : $(gpu_perf_level)"
	say "  current clock     : $(gpu_clock)"
	if [ -f "$CLOCK_SERVICE" ]; then
		say "  clock service     : $(systemctl is-enabled amdgpu-performance.service 2>/dev/null || echo unknown)"
	fi
	say ""

	say "Backups"
	if [ -f "$GRUB_BACKUP" ]; then
		say "  ${GRUB_BACKUP}"
		grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_BACKUP" | sed 's/^/    /'
	else
		say "  (none yet - the first --apply creates one)"
	fi
}

# ---------------------------------------------------------------- actions ---

backup_grub() {
	if [ -f "$GRUB_BACKUP" ]; then
		say "  backup already exists: ${GRUB_BACKUP}"
		return 0
	fi
	mkdir -p "$STATE_DIR"
	cp -a /etc/default/grub "$GRUB_BACKUP"
	ok "backed up /etc/default/grub -> ${GRUB_BACKUP}"
}

apply_amdgpu() {
	say "Switching the display GPU from radeon to amdgpu"
	say ""

	pg=$(primary_gpu) || { err "no display controller found"; return 1; }
	vend=$(printf '%s' "$pg" | cut -d: -f1)
	drv=$(printf '%s' "$pg" | cut -d: -f2)   # PCI address follows, but these two
	                                         # fields never contain a colon

	if [ "$vend" != "0x1002" ]; then
		err "the display GPU is $(vendor_name "$vend"), not AMD - nothing to switch"
		return 1
	fi
	if [ "$drv" = "amdgpu" ]; then
		ok "already on amdgpu; no change needed"
		return 0
	fi

	backup_grub

	if grep -q 'amdgpu.dc=1' /etc/default/grub 2>/dev/null; then
		ok "kernel parameters already present"
	else
		sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${CIK_PARAMS}\"|" \
			/etc/default/grub
		if ! grep -q 'amdgpu.dc=1' /etc/default/grub; then
			err "could not edit /etc/default/grub"
			return 1
		fi
		ok "added to GRUB_CMDLINE_LINUX_DEFAULT: ${CIK_PARAMS}"
	fi

	say "  regenerating boot configuration..."
	if ! update-grub >/tmp/fix-grub.log 2>&1; then
		err "update-grub failed; see /tmp/fix-grub.log"
		return 1
	fi
	ok "grub.cfg regenerated"
	say ""
	warn "A reboot is required for the new driver to take effect."
	warn "If the machine does not reach a graphical session, boot into the"
	warn "previous kernel from the GRUB menu and run: $0 --revert"
	return 0
}

revert_all() {
	if [ ! -f "$GRUB_BACKUP" ]; then
		err "no backup at ${GRUB_BACKUP}; nothing to restore"
		say "  To undo by hand: remove radeon.cik_support / amdgpu.cik_support /"
		say "  amdgpu.dc from GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub,"
		say "  then run update-grub."
		return 1
	fi
	cp -a "$GRUB_BACKUP" /etc/default/grub
	ok "restored /etc/default/grub from backup"
	if ! update-grub >/tmp/fix-grub.log 2>&1; then
		err "update-grub failed; see /tmp/fix-grub.log"
		return 1
	fi
	ok "grub.cfg regenerated"
	warn "Reboot to return to the previous driver."
	return 0
}

perf_on() {
	if [ ! -e /sys/class/drm/card0/device/power_dpm_force_performance_level ]; then
		err "this GPU exposes no performance level control"
		return 1
	fi
	cat >"$CLOCK_SERVICE" <<'EOF'
# Pin the GPU to its highest clock state.
#
# amdgpu on CIK (Kaveri) initialises DPM but never exports the frequency tables,
# so the governor cannot pick a state on demand: the GPU jumps to ~520 MHz for
# an instant under load and falls back to the 354 MHz floor.
#
# Cost: the GPU no longer idles down, so it draws full power and runs hot.
[Unit]
Description=Pin the AMD GPU to high performance
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Retry briefly: the service is ordered after udev-settle, but a slow disk or a
# deferred amdgpu probe can still mean card0 has no hwmon entry yet when this
# runs. Without the retry the loop below would match no file, succeed silently,
# and leave the GPU at its floor clock with nothing in the journal to show it.
ExecStart=/bin/sh -c 'for i in $(seq 1 50); do for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do [ -w "$f" ] && echo high > "$f" && exit 0; done; sleep 0.2; done; echo "no writable power_dpm_force_performance_level found" >&2; exit 1'

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable --now amdgpu-performance.service >/dev/null 2>&1
	ok "GPU pinned to high performance (current clock: $(gpu_clock))"
	return 0
}

perf_off() {
	if systemctl list-unit-files amdgpu-performance.service >/dev/null 2>&1 &&
	   systemctl is-enabled amdgpu-performance.service >/dev/null 2>&1; then
		systemctl disable --now amdgpu-performance.service >/dev/null 2>&1
		ok "clock service disabled"
	fi
	rm -f "$CLOCK_SERVICE"
	echo auto >/sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
	systemctl daemon-reload
	ok "GPU back to automatic clock management (current clock: $(gpu_clock))"
	return 0
}

# ------------------------------------------------------------- interactive ---

menu() {
	show_status
	hr
	say "What would you like to do?"
	say ""
	say "  1) Switch radeon -> amdgpu (adds ${CIK_PARAMS})"
	say "     Use this when the login screen stops at a flashing cursor."
	say "  2) Pin the GPU to high performance"
	say "     Use this when 3D applications run at roughly half speed."
	say "  3) Restore the original kernel command line"
	say "  4) Return the GPU to automatic clock management"
	say "  5) Show status only"
	say ""
	printf 'Choice [1-5]: '
	read -r choice

	case "$choice" in
		1) hr; apply_amdgpu ;;
		2) hr; perf_on ;;
		3) hr; revert_all ;;
		4) hr; perf_off ;;
		5) : ;;
		*) err "invalid choice"; exit 1 ;;
	esac
}

# ---------------------------------------------------------------- dispatch ---

need_root

case "${1:---interactive}" in
	--status)  show_status ;;
	--apply)   apply_amdgpu ;;
	--revert)  revert_all ;;
	--perf)
		case "${2:-}" in
			on)  perf_on ;;
			off) perf_off ;;
			*)   err "usage: $0 --perf on|off"; exit 1 ;;
		esac
		;;
	--interactive) menu ;;
	-h|--help)
		sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
		;;
	*) err "unknown option: $1 (try --help)"; exit 1 ;;
esac
FIXGRUB
	chmod 755 /usr/local/bin/sway-everforest-fix-grub
	register_file /usr/local/bin/sway-everforest-fix-grub
	return 0
}

write_picker() {
	# One icon, two jobs, chosen by mouse button:
	#   left  - full-screen screenshot to the clipboard (+ a file)
	#   right - drag a region, screenshot that to the clipboard
	# The colour dropper is a separate pill and takes a single click.
	local dest="/usr/local/bin/sway-everforest-shot"
	cat >"${dest}" <<'SHOT'
#!/bin/sh
# Screenshot helper behind the bar button.
#   sway-everforest-shot          full screen -> clipboard + file
#   sway-everforest-shot region   drag a region -> clipboard + file
# Every branch exits explicitly; falling through used to run a second capture.
export LC_ALL=C

notify() {
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -a Everforest -t "${3:-2000}" "$1" "$2"
	fi
}

fail() { notify "$1" "$2" 3000; exit 1; }

save_and_copy() {
	_src="$1"
	dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
	file=""
	if mkdir -p "${dir}" 2>/dev/null; then
		file="${dir}/$(date +%Y-%m-%d_%H-%M-%S).png"
		cp -f "${_src}" "${file}" 2>/dev/null || file=""
	fi
	if command -v wl-copy >/dev/null 2>&1 &&
		wl-copy --type image/png <"${_src}" 2>/dev/null; then
		if [ -n "${file}" ]; then
			notify "Screenshot" "Copied to clipboard and saved"
		else
			notify "Screenshot" "Copied to clipboard"
		fi
		exit 0
	fi
	if [ -n "${file}" ]; then
		notify "Screenshot" "Saved to ${file} (clipboard unavailable)"
		exit 0
	fi
	fail "Screenshot" "could not copy or save the capture"
}

command -v grim >/dev/null 2>&1 || fail "Screenshot" "grim is not installed"
tmp=$(mktemp /tmp/shot-XXXXXX.png) || exit 1
trap 'rm -f "${tmp}"' EXIT INT TERM

case "${1:-full}" in
region)
	command -v slurp >/dev/null 2>&1 || fail "Screenshot" "slurp is not installed"
	geom=$(slurp 2>/dev/null) || exit 0
	[ -n "${geom}" ] || exit 0
	grim -g "${geom}" "${tmp}" 2>/dev/null || fail "Screenshot" "capture failed"
	;;
*)
	grim "${tmp}" 2>/dev/null || fail "Screenshot" "capture failed"
	;;
esac

save_and_copy "${tmp}"
SHOT
	chmod 755 "${dest}"
	register_file "${dest}"

	# Single-click colour dropper. slurp's -p mode picks one pixel and returns
	# as soon as the button is released; the rectangle mode (no -p) is what
	# made it feel like a drag selection before.
	local pck="/usr/local/bin/sway-everforest-pick"
	cat >"${pck}" <<'PICK'
#!/bin/sh
# Pick the colour under a single click and copy its hex value.
export LC_ALL=C

say() {
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -a Everforest -t "${3:-2500}" "$1" "$2"
	fi
	exit "${4:-0}"
}

command -v grim >/dev/null 2>&1 || say "Colour pick" "grim is not installed" 3000 1
command -v slurp >/dev/null 2>&1 || say "Colour pick" "slurp is not installed" 3000 1

geom=$(slurp -p 2>/dev/null) || exit 0
[ -n "${geom}" ] || exit 0

tmp=$(mktemp /tmp/pick-XXXXXX.png) || exit 1
trap 'rm -f "${tmp}"' EXIT INT TERM

grim -g "${geom}" "${tmp}" 2>/dev/null || say "Colour pick" "capture failed" 3000 1

if command -v magick >/dev/null 2>&1; then CONV=magick
elif command -v convert >/dev/null 2>&1; then CONV=convert
else say "Colour pick" "ImageMagick is not installed" 3000 1; fi

hex=$("${CONV}" "${tmp}" -format "%[hex:p{0,0}]" info: 2>/dev/null |
	tr -d '\n' | tr 'A-F' 'a-f' | cut -c1-6)
[ -n "${hex}" ] || say "Colour pick" "could not read the pixel" 3000 1

if command -v wl-copy >/dev/null 2>&1 && printf '#%s' "${hex}" | wl-copy 2>/dev/null; then
	say "Colour copied" "#${hex}" 2000 0
fi
say "Colour read" "#${hex} (clipboard unavailable)" 3000 1
PICK
	chmod 755 "${pck}"
	register_file "${pck}"
	return 0
}
write_bash_extras() {
	local rc="${HOME_DIR}/.bashrc"
	local marker_begin="# >>> sway-everforest >>>"
	local marker_end="# <<< sway-everforest <<<"

	[[ -f "${rc}" ]] || touch "${rc}"
	chown_user "${rc}"

	if grep -qF "${marker_begin}" "${rc}" 2>/dev/null; then
		ui_dim "bash prompt already configured in ${rc}"
		return 0
	fi

	backup_path "${rc}"
	{
		printf '\n%s\n' "${marker_begin}"
		cat <<'BASHRC'
# Everforest prompt (sway rice) - remove by running the installer --uninstall
__ef_prompt() {
	local reset=$'\033[0m'
	local green=$'\033[38;2;167;192;128m'
	local blue=$'\033[38;2;127;187;179m'
	local grey=$'\033[38;2;122;132;120m'
	local lime=$'\033[38;2;185;255;102m'
	local yellow=$'\033[38;2;219;188;127m'
	# \w shows the working directory (~ for $HOME), the yellow plus the path so
	# it stands out from the user@host part.
	PS1="${green}╭─${lime}\$${reset}${green}\u${reset}${blue}@\h${reset} ${yellow}\w${reset} ${grey}\t${reset}\n${green}╰─${lime}\$${reset} "
}
PROMPT_COMMAND="__ef_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
export EDITOR="${EDITOR:-nano}"
BASHRC
		printf '%s\n' "${marker_end}"
	} >>"${rc}"
	chown_user "${rc}"
	register_file "${rc}"
	ui_ok "Everforest prompt added to ${rc}"
}

# ---------------------------------------------------------------------
