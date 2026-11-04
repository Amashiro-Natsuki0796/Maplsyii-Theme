# =====================================================================
#  Shell extras: the "mf" fetch script and the Everforest prompt
# =====================================================================

write_mf() {
	local dest="/usr/local/bin/mf" tmp
	tmp="$(mktemp)"
	cat >"${tmp}" <<'MFSCRIPT'
#!/usr/bin/env bash
# mf - minimal fetch for the Everforest i3 rice (Debian)
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

de="${XDG_CURRENT_DESKTOP:-i3}"
[[ -z "$de" ]] && de="i3"
case "${de,,}" in
	*sway*) de="sway" ;;
	*i3*)   de="i3" ;;
	*)      de="${de,,}" ;;
esac
# i3 runs on X11; report the server the session actually sits on.
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
if have xrandr; then
	# The first mode flagged with '*' is the active one on the primary output.
	res="$(xrandr 2>/dev/null | awk '/^[A-Za-z].* connected/{out=$1} /^ +[0-9]+x[0-9]+/{if ($0 ~ /\*/ && out != "") {print $1; exit}}')"
fi
if [[ -z "${res}" ]] && have xdpyinfo; then
	res="$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')"
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
	# Tiny helper for the bar "launcher" module: prints
	# "NN% MEM · NN% CPU" so the pill shows live figures without the bar
	# having to run a shell pipeline of its own.
	local dest="/usr/local/bin/i3-everforest-stats"
	cat >"${dest}" <<'STATS'
#!/bin/sh
# Memory and CPU usage for the bar launcher pill.
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
	cat >/usr/local/bin/i3-everforest-notifications <<'NOTIF'
#!/bin/sh
# Left click  : list notification history in a menu
# Right click : toggle do-not-disturb
#   history     show past notifications (rofi list, click to dismiss one)
#   toggle      switch do-not-disturb on/off
#   dismiss     clear everything currently on screen
# Dunst is the notification daemon on X11; dunstctl is its control channel.
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-everforest-dnd"
history="${XDG_STATE_HOME:-$HOME/.local/state}/i3-everforest/notifications.log"

dnd_on() { [ -e "${state}" ]; }

notify() {
	# --hint=int:transient:1 keeps this helper's own feedback out of the
	# history it is about to read back.
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a i3-everforest-control -t 1500 \
			--hint=int:transient:1 "Notifications" "$1"
	exit 0
}

show_history() {
	# dunst keeps the history in memory; ask it directly. Falling back to the
	# shared log keeps the button useful on a machine where dunst is absent.
	rows=""
	if command -v dunstctl >/dev/null 2>&1; then
		# dunstctl history is a typed D-Bus tree:
		#   {"data":[[{"summary":{"type":"s","data":"..."}, ...}, ...]]}
		# so pull the summaries out with a real JSON parser; the old sed
		# could not cope with the nested structure and always came up empty.
		rows=$(dunstctl history 2>/dev/null |
			python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
items = (d.get("data") or [[]])[0] or []
for it in items:
    app = (it.get("appname") or {}).get("data") or ""
    if app == "i3-everforest-control":
        continue
    s = (it.get("summary") or {}).get("data") or ""
    b = (it.get("body") or {}).get("data") or ""
    if s:
        print(s if not b else s + "  -  " + b.splitlines()[0][:60])
' 2>/dev/null)
	fi
	if [ -z "${rows}" ]; then
		mkdir -p "$(dirname "${history}")" 2>/dev/null
		rows=$(tac "${history}" 2>/dev/null | head -50)
	fi
	if [ -z "${rows}" ]; then
		notify "No notifications yet"
	fi

	# Show the list. This is the left-click action, so it must always appear
	# when there is anything to show.
	# Size the list to its contents (capped at 16 rows) so a short history does
	# not open a half-empty window.
	nlines=$(printf '%s\n' "${rows}" | grep -c . 2>/dev/null || echo 1)
	[ "${nlines:-0}" -lt 1 ] 2>/dev/null && nlines=1
	# The compact rows fit 20 before the list gets taller than the screen.
	[ "${nlines:-0}" -gt 20 ] 2>/dev/null && nlines=20

	if command -v rofi >/dev/null 2>&1; then
		# A compact font and tighter rows fit roughly twice as much history in
		# the same window. Only this menu is overridden; the launcher keeps the
		# theme's 13pt/41px.
		line=$(printf '%s\n' "${rows}" |
			rofi -dmenu -i -p "Notifications" -theme i3-everforest \
				-theme-str 'window {width: 620px;}' \
				-theme-str "window {height: $((96 + nlines * 25))px;}" \
				-theme-str "listview {lines: ${nlines};}" \
				-theme-str 'element {padding: 1px 8px;}' \
				-theme-str 'element-icon {size: 16px; margin: 0 6px 0 0;}' \
				-theme-str '* {font: "JetBrains Mono 10";}' 2>/dev/null)
		[ -n "${line}" ] || exit 0
		act=$(printf 'Clear all history\nCancel\n' |
			rofi -dmenu -i -p "Action" -theme i3-everforest \
				-theme-str 'window {width: 320px;}' -theme-str 'listview {lines: 4;}' 2>/dev/null)
		[ "${act}" = "Clear all history" ] && : >"${history}"
	fi
	exit 0
}

set_dnd() {
	if dnd_on; then
		rm -f "${state}"
		command -v dunstctl >/dev/null 2>&1 && dunstctl set-paused false >/dev/null 2>&1
	else
		: >"${state}"
		command -v dunstctl >/dev/null 2>&1 && dunstctl set-paused true >/dev/null 2>&1
	fi
}

case "${1:-history}" in
	history|list) show_history ;;
	toggle)
		# Only one message should ever be on screen. Clear whatever is showing
		# first, otherwise the previous "on" is still up when "off" arrives and
		# both notifications appear stacked.
		if command -v dunstctl >/dev/null 2>&1; then
			dunstctl close-all >/dev/null 2>&1
		fi
		sleep 0.15
		# Turning DND on pauses dunst, and `set-paused true` discards whatever is
		# still queued - so the confirmation must be on screen before the pause
		# takes effect. dunst needs about a second to actually paint it.
		if dnd_on; then
			if command -v notify-send >/dev/null 2>&1; then
				notify-send -a Everforest -t 1500 "Notifications" "Do not disturb off"
			fi
			sleep 0.4
			set_dnd
		else
			if command -v notify-send >/dev/null 2>&1; then
				notify-send -a Everforest -t 1500 "Notifications" "Do not disturb on"
			fi
			sleep 1.2
			set_dnd
		fi
		exit 0
		;;
	dismiss|clear)
		# Middle click on the bell means "wipe notifications", not just "hide
		# what is on screen": clear the popups AND the stored history, otherwise
		# the list still shows everything afterwards.
		if command -v dunstctl >/dev/null 2>&1; then
			dunstctl close-all >/dev/null 2>&1
			dunstctl history-clear >/dev/null 2>&1
		fi
		# Keep the shared fallback log in step with dunst.
		: >"${history}" 2>/dev/null
		notify "Cleared"
		;;
	*) show_history ;;
esac
NOTIF
	chmod 755 /usr/local/bin/i3-everforest-notifications
	register_file /usr/local/bin/i3-everforest-notifications

	# --- clock: a calendar popup ---------------------------------------------
	cat >/usr/local/bin/i3-everforest-calendar <<'CAL'
#!/bin/sh
# Clock actions.
#
#   (default)   show the date as a desktop notification
#   terminal    open this month's calendar in a terminal window
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
	say "📅 ${day}" 6000 "${rest}
week ${week}"
	exit 0
fi

# Right click: the full month grid in a terminal.
term="st"
command -v "${term}" >/dev/null 2>&1 || term="xterm"
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

if [ "${term}" = "st" ]; then
	"${term}" -c i3-everforest-calendar -e sh -c "${cmd}" >/dev/null 2>&1 &
else
	"${term}" -T "Calendar" -e sh -c "${cmd}" >/dev/null 2>&1 &
fi
exit 0
CAL
	chmod 755 /usr/local/bin/i3-everforest-calendar
	register_file /usr/local/bin/i3-everforest-calendar

	# --- clock: left click = month + agenda in a float, right = tooltip-like
	# summary. A terminal for the calendar is heavy for a bar click, so the
	# left button opens a small GTK popup instead and the terminal stays
	# available from the keybinding.
	cat >/usr/local/bin/i3-everforest-clock-popup <<'CLK'
#!/bin/sh
# Calendar / date popup for the clock pill, rendered with rofi.
#
# A bespoke GTK window was used before, but clicks on it depended on GDK event
# delivery that this X11 setup does not reliably provide, so it could not be
# dismissed. rofi always handles its own input.
export LC_ALL=C

mode="${1:-month}"

say() {
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t 2500 "$1"
	exit 0
}

command -v rofi >/dev/null 2>&1 || say "rofi is not installed"

if [ "${mode}" = "date" ]; then
	# Weekday, full date and ISO week.
	body=$(date '+%A%n%d %B %Y%nweek %V')
	label=$(date '+%A %d %B %Y')
else
	# `cal` printed nothing under this locale, so build the grid in python.
	body=$(python3 - <<'PYCAL'
import calendar, datetime
t = datetime.date.today()
raw = calendar.TextCalendar(calendar.MONDAY).formatmonth(t.year, t.month)
# Line 0 is the month title (already the prompt), line 1 the weekday header.
print(chr(10).join(raw.splitlines()[1:]))
PYCAL
	)
	label=$(date '+%B %Y')
fi

# rofi -dmenu with -no-custom: the lines are display-only, Esc or a click
# outside closes it. The prompt carries the title.
printf '%s\n' "${body}" |
	rofi -dmenu -p "${label}" -no-custom -theme i3-everforest \
		-theme-str 'window {width: 340px; height: 320px;}' \
		-theme-str 'listview {lines: 9;}' \
		-theme-str 'element {padding: 0 8px; min-height: 22px;}' \
		2>/dev/null

exit 0
CLK
	chmod 755 /usr/local/bin/i3-everforest-clock-popup
	register_file /usr/local/bin/i3-everforest-clock-popup

	# --- system monitor: what clicking the CPU pill opens --------------------
	cat >/usr/local/bin/i3-everforest-sysinfo-monitor <<'MON'
#!/bin/sh
# Open a live view of CPU, memory and disk.
term="st"
command -v "${term}" >/dev/null 2>&1 || term=xterm
if ! command -v "${term}" >/dev/null 2>&1; then
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest "System monitor" "No terminal emulator found"
	exit 1
fi
if command -v btop >/dev/null 2>&1; then
	exec "${term}" -e btop
fi
exec "${term}" -e sh -c 'while :; do clear; echo "CPU / memory"; echo; top -bn1 | head -12; sleep 2; done'
MON
	chmod 755 /usr/local/bin/i3-everforest-sysinfo-monitor
	register_file /usr/local/bin/i3-everforest-sysinfo-monitor

	# --- wifi: scan and connect ----------------------------------------------
	cat >/usr/local/bin/i3-everforest-wifi <<'WIFI'
#!/bin/sh
# WiFi control for the bar, driven entirely by NetworkManager.
#
#   (no args)   left click:  pick a network and join it
#   config      right click: connection details (state, IP, signal, forget)
#
# nmcli owns the radio here: the installer flips NetworkManager.conf to
# managed=true and stops any ifupdown wpa_supplicant that would hold the
# interface. Passphrases go through `nmcli --ask`, so they are never passed on
# a command line (where they would show up in ps) and NM stores them itself.
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

# Current SSID, empty when disconnected.
active_ssid() {
	nmcli -t -f ACTIVE,SSID device wifi list 2>/dev/null |
		awk -F: '$1=="yes"{print $2; exit}'
}

# "SSID<TAB>SIGNAL<TAB>SECURED<TAB>ACTIVE", strongest first, one row per SSID.
scan_networks() {
	nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null |
		awk -F: 'NF>=4 && $2!="" {
			act = ($1=="*") ? "1" : "0"
			sec = ($4 ~ /WPA|WEP|802/) ? "1" : "0"
			sig = $3 + 0
			# Keep the strongest sighting of each SSID.
			if (!($2 in best) || sig > best[$2]) {
				best[$2] = sig; sect[$2] = sec; actv[$2] = act
			}
		}
		END {
			for (s in best)
				printf "%s\t%d\t%s\t%s\n", s, best[s], sect[s], actv[s]
		}' | sort -t"	" -k2,2nr
}

# Ask for a passphrase through rofi (masked) and hand it to nmcli on stdin so
# it never appears in the process list.
join_network() {
	ssid="$1"
	secured="$2"

	if [ "$secured" = "0" ]; then
		nmcli device wifi connect "$ssid" >/dev/null 2>&1 &&
			say "Connected to $ssid" 3000 0
		say "Could not join $ssid" 5000 1
	fi

	# Reuse NetworkManager's stored key when there is one.
	if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "$ssid"; then
		nmcli connection up id "$ssid" >/dev/null 2>&1 &&
			say "Connected to $ssid" 3000 0
	fi

	psk=$(rofi -dmenu -password -p "$ssid" -theme i3-everforest \
		-theme-str 'window {width: 420px; height: 90px;}' \
		-theme-str 'listview {lines: 0;}' \
		-theme-str 'mainbox {padding: 10px;}' \
		-theme-str 'entry {placeholder: "Password";}' \
		-no-click-to-exit 2>/dev/null)
	if [ -z "$psk" ]; then
		exit 0
	fi

	# `nmcli --ask` reads the secret from this pipe, so the value stays out of
	# argv. The trailing newline is what the prompt consumes.
	printf '%s\n' "$psk" |
		nmcli --ask device wifi connect "$ssid" >/dev/null 2>&1 &&
		say "Connected to $ssid" 3000 0
	say "Could not join $ssid (wrong password?)" 5000 1
}

show_list() {
	have_nm || say "NetworkManager is not running"

	dev=$(wifi_dev)
	[ -n "$dev" ] || say "No wireless adaptor detected"

	# Read the snapshot a background refresher keeps warm (see
	# i3-everforest-wifi-cache). Falling back to a live call is only needed the
	# very first time, before the cache exists.
	cache="${XDG_RUNTIME_DIR:-/tmp}/i3-everforest-wifi.cache"
	snapshot=""
	if [ -f "${cache}" ]; then
		snapshot=$(cat "${cache}" 2>/dev/null)
	fi
	if [ -z "${snapshot}" ]; then
		snapshot=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null)
	fi
	cur=$(printf '%s\n' "$snapshot" | awk -F: '$1=="*"{print $2; exit}')
	rows=$(printf '%s\n' "$snapshot" | awk -F: 'NF>=4 && $2!="" {
		act = ($1=="*") ? "1" : "0"
		sec = ($4 ~ /WPA|WEP|802/) ? "1" : "0"
		sig = $3 + 0
		if (!($2 in best) || sig > best[$2]) {
			best[$2] = sig; sect[$2] = sec; actv[$2] = act
		}
	}
	END {
		for (s in best)
			printf "%s\t%d\t%s\t%s\n", s, best[s], sect[s], actv[s]
	}' | sort -t"	" -k2,2nr)
	[ -n "$rows" ] || say "No networks found (is the radio on?)"

	# Display: SSID, signal%, and the security type. No leading glyphs - the
	# list is easier to scan when the names line up.
	display=$(printf '%s\n' "$rows" | awk -F'\t' -v cur="$cur" '
		{
			sig = $2 + 0
			star = ($4 == "1" || $1 == cur) ? "  *" : ""
			lock = ($3 == "1") ? "WPA" : "open"
			printf "%-26s %3d%%  %-4s%s\t%s\n", $1, sig, lock, star, $1
		}')

	tmp_list=$(mktemp /tmp/i3-ef-wifi-XXXXXX)
	printf '%s\n' "$display" | cut -f1 >"${tmp_list}"
	sel=$(rofi -dmenu -p "WiFi" -theme i3-everforest \
		-theme-str 'window {width: 500px; height: 340px;}' \
		-theme-str 'listview {lines: 9;}' \
		-input "${tmp_list}" 2>/dev/null)
	rm -f "${tmp_list}"
	[ -n "$sel" ] || exit 0

	# Map the chosen display row back to the raw SSID.
	ssid=$(printf '%s\n' "$display" | awk -F'\t' -v s="$sel" '$1==s{print $2; exit}')
	[ -n "$ssid" ] || exit 0

	secured=$(printf '%s\n' "$rows" | awk -F'\t' -v s="$ssid" '$1==s{print $3; exit}')
	join_network "$ssid" "${secured:-1}"
}

show_config() {
	have_nm || say "NetworkManager is not running"

	dev=$(wifi_dev)
	[ -n "$dev" ] || say "No wireless adaptor detected"

	# Collect everything NetworkManager knows about the link.
	fields=$(nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR,\
IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP4.ROUTE device show "$dev" 2>/dev/null)

	get() {
		# Array fields are reported as "KEY[1]:", scalars as "KEY:".
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

	# Signal for the active link, from the background cache when present.
	cache="${XDG_RUNTIME_DIR:-/tmp}/i3-everforest-wifi.cache"
	link=""
	if [ -f "${cache}" ]; then
		link=$(awk -F: '$1=="*"{print; exit}' "${cache}" 2>/dev/null)
	fi
	if [ -z "${link}" ]; then
		link=$(nmcli -t -f IN-USE,SSID,SIGNAL,CHAN,RATE device wifi list 2>/dev/null |
			awk -F: '$1=="*"{print; exit}')
	fi
	ssid=$(printf '%s' "$link" | cut -d: -f2)
	sig=$(printf '%s' "$link" | cut -d: -f3)
	chan=$(iw dev "$dev" info 2>/dev/null | awk '/channel/{print $2; exit}')
	sec=$(printf '%s' "$link" | cut -d: -f4)
	rate=$(iw dev "$dev" link 2>/dev/null |
		awk '/bitrate/{print $2, $3; exit}')

	speed=$(nmcli -t -f GENERAL.CONNECTION device show "$dev" 2>/dev/null >/dev/null && \
		iw dev "$dev" link 2>/dev/null | awk '/bitrate/{print $2, $3; exit}')
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
Security  : ${sec:-n/a}
Rate      : ${rate:-n/a}
Link speed: ${speed:-n/a}"

	# Menu entries, each mapped to an action below.
	menu="Reconnect
Disconnect
Forget this network
Open advanced editor
Copy IP to clipboard
Close"

	choice=$(printf '%s\n' "$menu" |
		rofi -dmenu -p "WiFi: ${ssid:-$dev}" -mesg "$info" -theme i3-everforest \
			-theme-str 'window {width: 540px; height: 430px;}' \
			-theme-str 'listview {lines: 6;}' \
			-theme-str 'textbox {font: "JetBrains Mono 10";}' \
			-theme-str 'message {border: 1px 0px 0px 0px; padding: 8px;}' \
			2>/dev/null)
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
		# nm-connection-editor ships with network-manager-gnome and gives the
		# full set of options (IPv4 method, DNS, routes, security).
		if command -v nm-connection-editor >/dev/null 2>&1; then
			nm-connection-editor >/dev/null 2>&1 &
		elif command -v nmtui >/dev/null 2>&1; then
			command -v st >/dev/null 2>&1 &&
				st -e nmtui >/dev/null 2>&1 &
		else
			say "No connection editor installed" 4000 1
		fi
		exit 0
		;;
	Copy\ IP*)
		if [ -n "$ip" ] && command -v xclip >/dev/null 2>&1; then
			printf '%s' "$ip" | xclip -selection clipboard 2>/dev/null
			say "Copied $ip" 2500 0
		fi
		say "No IP to copy" 3000 1
		;;
	esac
	exit 0
}

case "${1:-list}" in
config) show_config ;;
*) show_list ;;
esac
WIFI
	chmod 755 /usr/local/bin/i3-everforest-wifi

	# A tiny refresher keeps NetworkManager's wifi list in a file. nmcli blocks
	# for ~10s whenever its internal cache has expired, and paying that on a
	# click is unacceptable; polling in the background means the popup always
	# reads a ready-made snapshot.
	cat >/usr/local/bin/i3-everforest-wifi-cache <<'WCACHE'
#!/bin/sh
# Refresh the wifi snapshot every 20s so the bar's popup opens instantly.
export LC_ALL=C
cache="${XDG_RUNTIME_DIR:-/tmp}/i3-everforest-wifi.cache"
while :; do
	nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list \
		>/tmp/.wf.$$ 2>/dev/null &&
		mv /tmp/.wf.$$ "${cache}" 2>/dev/null
	sleep 20
done
WCACHE
	chmod 755 /usr/local/bin/i3-everforest-wifi-cache
	register_file /usr/local/bin/i3-everforest-wifi-cache
	register_file /usr/local/bin/i3-everforest-wifi

	# The bar's wifi control is nmcli-only, so NetworkManager has to own the
	# radio. On a default Debian install NetworkManager.conf ships
	# `managed=false`, which leaves the adaptor to ifupdown and makes every
	# nmcli call fail; flipping it (and stopping an ifupdown wpa_supplicant
	# that already holds the interface) is what makes the bar's wifi work.
	if [[ ${OPT_DRY_RUN} -eq 0 ]]; then
		local nmconf="/etc/NetworkManager/NetworkManager.conf"
		if [[ -f "${nmconf}" ]] && grep -q '^managed=false' "${nmconf}"; then
			sed -i 's/^managed=false/managed=true/' "${nmconf}"
			ui_ok "NetworkManager now manages all devices"
			systemctl restart NetworkManager >/dev/null 2>&1 || true
		fi

		# Stop a stray supplicant started by ifupdown: NetworkManager's own
		# instance cannot grab an interface that is already taken, and the
		# bar's wifi button then scans nothing.
		#
		# `kill ... && ui_dim` used to abort the whole install: under `set -e`
		# a failing kill (already gone, or not ours) makes the loop's exit
		# status non-zero. Collect the pids first and never let a failure
		# escape.
		if command -v pgrep >/dev/null 2>&1; then
			local stray
			stray="$(pgrep -f 'wpa_supplicant.*-i wlp' 2>/dev/null || true)"
			for pid in ${stray}; do
				if kill "${pid}" 2>/dev/null; then
					ui_dim "stopped a stray wpa_supplicant (pid ${pid})"
				fi
			done || true
			# NetworkManager restarts its own instance once the port is free.
			if [[ -n "${stray}" ]]; then
				sleep 1
				systemctl restart NetworkManager >/dev/null 2>&1 || true
			fi
		fi

		# The old setup granted sudo for wpa_cli/iw/dhcp; nmcli needs none.
		local sc="/etc/sudoers.d/i3-everforest-wifi"
		if [[ -f "${sc}" ]]; then
			rm -f "${sc}"
			ui_dim "removed the obsolete wifi sudoers rule"
		fi
	fi

	# --- input method: toggle whichever framework is actually running --------
	cat >/usr/local/bin/i3-everforest-ime <<'IME'
#!/bin/sh
# Input method control for the bar.
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

# "keyboard-us" -> "English (US)", "pinyin" -> "Pinyin"
pretty() {
	case "$1" in
	keyboard-us) echo "English (US)" ;;
	keyboard) echo "English" ;;
	pinyin) echo "Pinyin (Chinese)" ;;
	*) echo "$1" ;;
	esac
}

do_toggle() {
	if have_fcitx; then
		fcitx5-remote -t >/dev/null 2>&1 && exit 0
	fi
	if command -v ibus >/dev/null 2>&1 && pgrep -x ibus-daemon >/dev/null 2>&1; then
		ibus engine "$(ibus engine | grep -q xkb && echo pinyin || echo xkb:us::eng)" \
			>/dev/null 2>&1 && exit 0
	fi
	if command -v setxkbmap >/dev/null 2>&1; then
		cur=$(setxkbmap -query 2>/dev/null | sed -n 's/^layout: *//p')
		case "${cur}" in
		us*) setxkbmap -layout us,ru >/dev/null 2>&1 &&
			setxkbmap -layout ru >/dev/null 2>&1 ;;
		*)   setxkbmap -layout us >/dev/null 2>&1 ;;
		esac
	fi
	if command -v fcitx5 >/dev/null 2>&1 || command -v ibus >/dev/null 2>&1; then
		say "No IM daemon is running"
	fi
	say "No input method installed"
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

	# Enabled input methods, from fcitx5's profile.
	ims=""
	if [ -f "${HOME}/.config/fcitx5/profile" ]; then
		ims=$(awk -F= '/^Name=/ && !/^Name=Default/ {print $2}' \
			"${HOME}/.config/fcitx5/profile" 2>/dev/null | paste -sd', ' -)
	fi

	# The trigger key comes from the installed hotkey.conf.
	hotkey=""
	if [ -f "${HOME}/.config/fcitx5/conf/hotkey.conf" ]; then
		hotkey=$(awk -F= '/^[0-9]*=Control\+space/ {print "Ctrl+Space"; exit}' \
			"${HOME}/.config/fcitx5/conf/hotkey.conf" 2>/dev/null)
	fi
	[ -n "${hotkey}" ] || hotkey="Ctrl+Space"

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

	choice=$(printf '%s\n' "${menu}" |
		rofi -dmenu -p "Input method" -mesg "${info}" -theme i3-everforest \
			-theme-str 'window {width: 520px; height: 380px;}' \
			-theme-str 'listview {lines: 5;}' 2>/dev/null)
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
		setsid fcitx5 -d --disable virtualkeyboard,emoji,table,spell,kimpanel,quickphrase,unicode,clipboard,notificationitem,fcitx4frontend,ibusfrontend,wayland,waylandim >/dev/null 2>&1 </dev/null &
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
	chmod 755 /usr/local/bin/i3-everforest-ime
	register_file /usr/local/bin/i3-everforest-ime

	return 0
}

write_sysinfo() {
	# Two helpers for the bar's right-hand pills, matching the reference
	# layout: disk+CPU, and the P/V temperature readout.
	local si="/usr/local/bin/i3-everforest-sysinfo"
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
# `--cpu` prints only the CPU figure, which the bar's line graph samples.
# The default output is the memory reading alone: CPU is shown as a graph,
# so printing its percentage as well would be noise.
if [ "${1:-}" = "--cpu" ]; then
	printf '%s\n' "$cpu"
	exit 0
fi
printf '%s %s%%\n' "" "$mem"
SYSINFO
	chmod 755 "${si}"
	register_file "${si}"

	local tp="/usr/local/bin/i3-everforest-temps"
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

write_input() {
	# X11 has no sway-style `input` blocks, so the same device settings are
	# applied with xinput/setxkbmap at session start:
	#   touchpad  - tap to click, natural scrolling, disable while typing
	#   keyboard  - Caps Lock acts as Ctrl (xkb option ctrl:nocaps)
	# The script is idempotent and silent when a device is absent (a desktop
	# has no touchpad), so it can run unconditionally from i3's autostart.
	local dest="/usr/local/bin/i3-everforest-input"
	cat >"${dest}" <<'INPUT'
#!/bin/sh
# Apply the rice's input-device settings on X11.
#
# sway expresses these as `input type:touchpad { ... }` and
# `input type:keyboard { xkb_options ctrl:nocaps }`; on X11 the equivalents
# are xinput properties and an XKB option. Every step is best-effort: a
# machine without a touchpad must not produce errors.

# --- Caps Lock as Ctrl -------------------------------------------------------
# ctrl:nocaps is the same XKB option sway's xkb_options uses. setxkbmap
# replaces the whole layout, so the current one is preserved.
if command -v setxkbmap >/dev/null 2>&1; then
	cur_layout=$(setxkbmap -query 2>/dev/null | sed -n 's/^layout: *//p')
	cur_variant=$(setxkbmap -query 2>/dev/null | sed -n 's/^variant: *//p')
	cur_options=$(setxkbmap -query 2>/dev/null | sed -n 's/^options: *//p')

	# Keep any options that are already set, but never duplicate ctrl:nocaps.
	opts="ctrl:nocaps"
	case ",${cur_options}," in
	*,ctrl:nocaps,*) opts="${cur_options}" ;;
	*) [ -n "${cur_options}" ] && opts="${cur_options},ctrl:nocaps" ;;
	esac

	if [ -n "${cur_layout}" ]; then
		if [ -n "${cur_variant}" ]; then
			setxkbmap -layout "${cur_layout}" -variant "${cur_variant}" \
				-option "${opts}" >/dev/null 2>&1 || true
		else
			setxkbmap -layout "${cur_layout}" -option "${opts}" \
				>/dev/null 2>&1 || true
		fi
	else
		setxkbmap -option "${opts}" >/dev/null 2>&1 || true
	fi
fi

# --- touchpad ---------------------------------------------------------------
# xinput lists devices by name; a device is a touchpad when it exposes the
# libinput "Tapping Enabled" property.
if command -v xinput >/dev/null 2>&1; then
	xinput list --name-only 2>/dev/null | while IFS= read -r dev; do
		[ -n "$dev" ] || continue
		props=$(xinput list-props "$dev" 2>/dev/null) || continue
		case "$props" in
		*"Tapping Enabled"*) ;;
		*) continue ;;   # not a touchpad
		esac
		# tap to click
		xinput set-prop "$dev" "libinput Tapping Enabled" 1 >/dev/null 2>&1 || \
			xinput set-prop "$dev" "Tapping Enabled" 1 >/dev/null 2>&1 || true
		# natural scrolling
		xinput set-prop "$dev" "libinput Natural Scrolling Enabled" 1 \
			>/dev/null 2>&1 || \
			xinput set-prop "$dev" "Natural Scrolling Enabled" 1 \
			>/dev/null 2>&1 || true
		# disable-while-typing (dwt)
		xinput set-prop "$dev" "libinput Disable While Typing Enabled" 1 \
			>/dev/null 2>&1 || true
	done
fi

exit 0
INPUT
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_network() {
	# Waybar's native `network` module picks one of three glyphs:
	#   wifi         \uf1eb
	#   ethernet     \uf09e
	#   disconnected \uf00d
	# This helper reproduces that decision so the bar can render the same
	# thing on X11 without a native module.
	local dest="/usr/local/bin/i3-everforest-network"
	cat >"${dest}" <<'NET'
#!/bin/sh
# Network glyph for the bar: wifi, ethernet, or the no-connection cross.
export LC_ALL=C

WIFI='\357\207\253'      # U+F1EB wifi
ETH='\357\202\236'       # U+F09E ethernet
OFF='\357\200\215'       # U+F00D no connection

# While a connection is being established the helper touches this flag; the bar
# then renders a spinner instead of the static glyph.
STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u 2>/dev/null || echo 0)}"
BUSY_FLAG="${STATE_DIR:-/tmp}/i3-everforest-wifi-busy"
if [ -e "${BUSY_FLAG}" ]; then
	# Braille spinner, eight frames. The frame is chosen from the clock so the
	# helper stays stateless.
	now=$(date +%s%N 2>/dev/null || echo 0)
	idx=$(( (now / 130000000) % 8 ))
	case "${idx}" in
	0) f='\357\240\213' ;; 1) f='\357\240\231' ;;
	2) f='\357\240\271' ;; 3) f='\357\240\270' ;;
	4) f='\357\240\274' ;; 5) f='\357\240\264' ;;
	6) f='\357\240\246' ;; *) f='\357\240\247' ;;
	esac
	printf '%b\n' "${f}"
	exit 0
fi

# Decide which glyph to show. waybar's own module reports "disconnected" only
# when there is genuinely no link, and a desktop rice on a laptop is almost
# always on wifi - so the default is the wifi glyph and the cross is reserved
# for a real, detected disconnection.

# Decide from the *default route*, which is the interface traffic actually
# uses. nmcli is a poor proxy: a card can be marked `unmanaged` (or be driven
# by iwd/wpa_supplicant directly) while still carrying all the traffic.
default_dev() {
	ip route show default 2>/dev/null | awk '/^default/{
		for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i+1); exit }
	}'
}

is_wireless() {
	[ -n "$1" ] || return 1
	[ -d "/sys/class/net/$1/wireless" ] || [ -d "/sys/class/net/$1/phy80211" ]
}

DEV=$(default_dev)
if [ -n "${DEV}" ]; then
	if is_wireless "${DEV}"; then
		printf '%b\n' "${WIFI}"
	else
		printf '%b\n' "${ETH}"
	fi
	exit 0
fi

# No default route: fall back to NetworkManager's opinion.
if command -v nmcli >/dev/null 2>&1; then
	state=$(nmcli -t -f STATE general 2>/dev/null)
	case "${state}" in
	connected*)
		if nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null |
			grep -q ':wifi:connected'; then
			printf '%b\n' "${WIFI}"
		else
			printf '%b\n' "${ETH}"
		fi
		exit 0
		;;
	esac
fi

# No NetworkManager: read the kernel. A machine with a wireless interface is
# treated as wifi-first, which is what this rice assumes.
have_wifi=0; wifi_up=0; wired_up=0
for dev in /sys/class/net/*; do
	[ -e "$dev" ] || continue
	case "${dev##*/}" in
	lo) continue ;;
	esac
	if [ -d "${dev}/wireless" ] || [ -d "${dev}/phy80211" ]; then
		have_wifi=1
		[ "$(cat "${dev}/operstate" 2>/dev/null)" = "up" ] && wifi_up=1
	elif [ -e "${dev}/device" ] && [ ! -d "${dev}/wireless" ]; then
		[ "$(cat "${dev}/carrier" 2>/dev/null)" = "1" ] && wired_up=1
	fi
done

if [ "${wifi_up}" -eq 1 ]; then
	printf '%b\n' "${WIFI}"
elif [ "${wired_up}" -eq 1 ]; then
	printf '%b\n' "${ETH}"
elif [ "${have_wifi}" -eq 1 ]; then
	# A wireless card exists but is down: still the wifi glyph, because the
	# pill is the "network" button, not a link-state indicator.
	printf '%b\n' "${WIFI}"
else
	printf '%b\n' "${WIFI}"
fi
NET
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_brightness() {
	# A bar module that renders nothing shifts every control after it. A
	# helper keeps the pill in place: internal backlight first, then ddcutil
	# for external screens, then a RandR gamma change, then a dim glyph.
	local dest="/usr/local/bin/i3-everforest-brightness"
	cat >"${dest}" <<'BRIGHT'
#!/bin/sh
# Screen brightness for the bar pill.
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

# X11 fallback: RandR brightness. Unlike sysfs/ddcutil this never fails
# silently - it is a software gamma change - so it always keeps the pill
# useful on a machine without a controllable backlight.
read_randr() {
	command -v xrandr >/dev/null 2>&1 || return 1
	v=$(xrandr --verbose 2>/dev/null | sed -n 's/^[[:space:]]*Brightness: *//p' | head -1)
	[ -n "$v" ] || return 1
	awk -v b="$v" 'BEGIN{printf "%d", b*100}'
}

set_randr() {
	command -v xrandr >/dev/null 2>&1 || return 1
	cur=$(read_randr) || cur=100
	case "$1" in
	+*) step=$(( ${1%\%+} )) ;;
	-*) step=$(( ${1%\%-} )) ;;
	*)  step=0 ;;
	esac
	if [ "$step" -eq 0 ]; then nxt=$cur; else nxt=$((cur + step)); fi
	[ "$nxt" -gt 100 ] && nxt=100
	[ "$nxt" -lt 10 ] && nxt=10
	val=$(awk -v n="$nxt" 'BEGIN{printf "%.2f", n/100}')
	for out in $(xrandr --query 2>/dev/null | awk '/ connected/{print $1}'); do
		xrandr --output "$out" --brightness "$val" >/dev/null 2>&1
	done
	return 0
}

case "$1" in
	up)
		set_backlight 5%+ && exit 0
		cur=$(read_ddc) && [ -n "$cur" ] && {
			nxt=$((cur + 10)); [ "$nxt" -gt 100 ] && nxt=100
			ddcutil setvcp 10 "$nxt" >/dev/null 2>&1
			exit 0
		}
		set_randr 10%+ && exit 0
		exit 0
		;;
	down)
		set_backlight 5%- && exit 0
		cur=$(read_ddc) && [ -n "$cur" ] && {
			nxt=$((cur - 10)); [ "$nxt" -lt 5 ] && nxt=5
			ddcutil setvcp 10 "$nxt" >/dev/null 2>&1
			exit 0
		}
		set_randr 10%- && exit 0
		exit 0
		;;
esac

p=$(read_backlight) || p=$(read_ddc) || p=$(read_randr)
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
	# Polybar's pulseaudio module exposes only the sink, but the reference
	# shows speaker and microphone together in one pill, so print both here.
	local dest="/usr/local/bin/i3-everforest-volume"
	{
		printf '%s\n' '#!/bin/sh'
		printf '%s\n' '# Speaker and microphone level for the bar volume pill.'
		printf '%s\n' 'command -v pactl >/dev/null 2>&1 || { printf "\357\200\246 n/a\n"; exit 0; }'
		printf '%s\n' ''
		printf '%s\n' 'sink=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o "[0-9]\\+%" | head -1)'
		printf '%s\n' 'src=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o "[0-9]\\+%" | head -1)'
		printf '%s\n' 'smute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -c yes)'
		printf '%s\n' 'rmute=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -c yes)'
		printf '%s\n' '[ -n "$sink" ] || sink="--"'
		printf '%s\n' '[ -n "$src" ] || src="--"'
		printf '%s\n' 'if [ "$smute" -eq 1 ]; then si="\357\200\246"; else si="\357\200\247"; fi'
		printf '%s\n' 'if [ "$rmute" -eq 1 ]; then mi="\357\204\261"; else mi="\357\204\260"; fi'
		printf '%s\n' 'printf "%s %b  %s %b\\n" "$sink" "$si" "$src" "$mi"'
	} >"${dest}"
	# The block above uses printf without a redirection on purpose built
	# strings only; the file itself is written by the surrounding >"${dest}".
	chmod 755 "${dest}"
	register_file "${dest}"
	return 0
}

write_picker() {
	# One icon, two jobs, chosen by mouse button:
	#   left  - full-screen screenshot to the clipboard (+ a file)
	#   right - drag a region, screenshot that to the clipboard
	# The colour dropper is a separate pill and takes a single click.
	#
	# X11 equivalent of grim/slurp/wl-copy: maim captures, slop selects the
	# region, xclip puts the PNG on the CLIPBOARD selection.
	# The clipboard owner itself: GTK advertises every image target at once,
	# which xclip cannot do (one target per process).
	cat >/usr/local/bin/i3-everforest-clip <<'CLIP'
#!/usr/bin/env python3
"""Hold the clipboard for an image or a string.

xclip serves a single target per process, so a screenshot copied as PNG only
appears in applications that ask for exactly image/png. A file manager asks for
image/bmp, and then "paste" looks empty. GTK can publish all the targets from
one owner, which is what this does.
"""
import os
import signal
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "text"
    value = sys.argv[2] if len(sys.argv) > 2 else ""

    clip = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)

    if mode == "text":
        clip.set_text(value, -1)
        Gtk.main()
        return 0

    # image: load once, publish as a pixbuf (GTK derives png/bmp/jpeg from it).
    try:
        pb = GdkPixbuf.Pixbuf.new_from_file(value)
    except Exception:
        return 1
    clip.set_image(pb)
    # Keep the file alive for as long as the clipboard holds it.
    Gtk.main()
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: Gtk.main_quit())
    sys.exit(main())
CLIP
	chmod 755 /usr/local/bin/i3-everforest-clip
	register_file /usr/local/bin/i3-everforest-clip
	local dest="/usr/local/bin/i3-everforest-shot"
	cat >"${dest}" <<'SHOT'
#!/bin/sh
# Screenshot helper behind the bar button.
#   i3-everforest-shot          full screen -> clipboard + file
#   i3-everforest-shot region   drag a region -> clipboard + file
# Every branch exits explicitly; falling through used to run a second capture.
export LC_ALL=C

notify() {
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -a Everforest -t "${3:-2000}" "$1" "$2"
	fi
	# A detached screenshot is invisible otherwise; flash the bar.
	if command -v i3-msg >/dev/null 2>&1; then
		i3-msg -q 'mode "default"' >/dev/null 2>&1 || true
	fi
}

CLIP_HELPER="/usr/local/bin/i3-everforest-clip"

# Clipboard for images and colours.
#
# xclip serves exactly one target per process, so a PNG-only clipboard shows
# nothing when a file manager asks for image/bmp. This helper owns the
# clipboard from GTK and advertises every format a paste target might request.
copy_image() {
	"${CLIP_HELPER}" image "$1"
}



copy_text() {
	"${CLIP_HELPER}" text "$1"
}

fail() { notify "$1" "$2" 3000; exit 1; }


fail() { notify "$1" "$2" 3000; exit 1; }


# Save a capture to ~/Pictures/Screenshots. The clipboard is deliberately not
# touched: a saved file can be dragged or opened, and silently overwriting the
# clipboard was never wanted.
save_shot() {
	_src="$1"
	dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
	# Sets the global `file` so the caller can hand it to an editor.
	file=""
	if mkdir -p "${dir}" 2>/dev/null; then
		file="${dir}/$(date +%Y-%m-%d_%H-%M-%S).png"
		cp -f "${_src}" "${file}" 2>/dev/null || file=""
	fi
	if [ -n "${file}" ]; then
		# Report the directory rather than the full path: the notification is
		# narrow, and the timestamp alone is enough to identify the file.
		notify "Screenshot" "Saved to ~/Pictures/Screenshots/$(basename "${file}")"
		exit 0
	fi
	fail "Screenshot" "could not save the capture to ${dir}"
}

# maim is the X11 screenshot tool; scrot/import are the fallbacks that ship
# with a stock X install.
capture() {
	# capture <output-file> [geometry]
	if command -v maim >/dev/null 2>&1; then
		if [ -n "${2:-}" ]; then
			maim -u -g "$2" "$1" 2>/dev/null
		else
			maim -u "$1" 2>/dev/null
		fi
		return $?
	fi
	if command -v scrot >/dev/null 2>&1; then
		if [ -n "${2:-}" ]; then
			scrot -a "$2" "$1" 2>/dev/null
		else
			scrot "$1" 2>/dev/null
		fi
		return $?
	fi
	if command -v import >/dev/null 2>&1; then
		if [ -n "${2:-}" ]; then
			import -window root -crop "$2" "$1" 2>/dev/null
		else
			import -window root "$1" 2>/dev/null
		fi
		return $?
	fi
	return 127
}

tmp=$(mktemp /tmp/shot-XXXXXX.png) || exit 1
trap 'rm -f "${tmp}"' EXIT INT TERM

# Modes, matching the three bindings the sway config uses:
#   full | clip          full screen -> clipboard + file
#   region               drag a region -> clipboard + file
#   region-clip          drag a region -> clipboard only  ($mod+Print)
#   region-swappy        drag a region -> clipboard, then swappy ($mod+Shift+Print)
mode="${1:-full}"

grab_region() {
	if ! command -v slop >/dev/null 2>&1; then
		fail "Screenshot" "slop is not installed"
	fi
	# Say that the crosshair is armed before blocking on the drag.
	notify "Screenshot" "Drag to select an area" 2500
	# slop prints "WxH+X+Y"; maim takes exactly that geometry.
	# slop only accepts %x %y %w %h %g %i %c after a '%'; the old
	# '%wx%h%+X%+Y' errored out and region capture never ran.
	set -- $(slop -f '%w %h %x %y' 2>/dev/null) || exit 0
	[ $# -eq 4 ] || exit 0
	geom="${1}x${2}+${3}+${4}"
	[ -n "${geom}" ] || exit 0
	capture "${tmp}" "${geom}" || fail "Screenshot" "capture failed"
}

case "${mode}" in
region|region-clip|region-swappy)
	grab_region
	;;
*)
	capture "${tmp}" || fail "Screenshot" "capture failed (is maim installed?)"
	;;
esac

# Every mode saves to ~/Pictures/Screenshots. The clipboard-only modes existed
# to mirror the Wayland recipe (grim - | wl-copy), but a saved file is what is
# actually useful here.
save_shot "${tmp}"

# swappy is an editor: hand it the saved file when that mode was asked for.
if [ "${mode}" = "region-swappy" ]; then
	if command -v swappy >/dev/null 2>&1 && [ -n "${file}" ]; then
		# swappy keeps reading the file, so it must outlive the trap.
		trap - EXIT INT TERM
		swappy -f "${file}" >/dev/null 2>&1 &
	else
		notify "Screenshot" "swappy is not installed" 3000
	fi
fi
SHOT
	chmod 755 "${dest}"
	register_file "${dest}"

	# Single-click colour dropper. slop's -p mode picks one pixel and returns
	# as soon as the button is released; the rectangle mode is what made it
	# feel like a drag selection.
	local pck="/usr/local/bin/i3-everforest-pick"
	cat >"${pck}" <<'PICK'
#!/bin/sh
# Pick the colour under a single click and copy its hex value.
#
# A GTK overlay is the wrong tool here: i3 tiles a normal window, so the overlay
# did not cover the screen and sampled the wrong place. Instead ask for a 1x1
# selection with an existing tool and read that pixel - no window of our own.
export LC_ALL=C

say() {
	command -v notify-send >/dev/null 2>&1 &&
		notify-send -a Everforest -t "${2:-2500}" "Colour pick" "$1"
	exit "${3:-0}"
}

# Announce before the selector grabs the screen.
say "Click the colour you want" 2200 0 &
sleep 0.3

tmp=$(mktemp /tmp/pick-XXXXXX.png) || exit 1
trap 'rm -f "${tmp}"' EXIT INT TERM

# slop with a 1x1 minimum: any click (or a hair of drag) returns a geometry.
geom=""
if command -v slop >/dev/null 2>&1; then
	geom=$(slop -t 0 -f '%x %y' 2>/dev/null) || geom=""
fi

if [ -n "${geom}" ]; then
	x=${geom% *}
	y=${geom#* }
	if command -v maim >/dev/null 2>&1; then
		maim -u -g "1x1+${x}+${y}" "${tmp}" 2>/dev/null
	fi
fi

# Fallback: maim's own region selector (also a single drag).
if [ ! -s "${tmp}" ]; then
	if command -v maim >/dev/null 2>&1; then
		maim -u -s -b 1 "${tmp}" 2>/dev/null || say "Colour pick" "selection cancelled" 2000 1
	fi
fi

[ -s "${tmp}" ] || say "Colour pick" "could not read that pixel" 3000 1

if command -v magick >/dev/null 2>&1; then CONV=magick
elif command -v convert >/dev/null 2>&1; then CONV=convert
else say "Colour pick" "ImageMagick is not installed" 3000 1; fi

hex=$("${CONV}" "${tmp}" -format '%[hex:p{0,0}]' info: 2>/dev/null |
	tr -d '\n' | tr 'A-F' 'a-f' | cut -c1-6)
[ -n "${hex}" ] || say "Colour pick" "could not read the pixel" 3000 1

# Text on the clipboard through the shared owner so it survives this process.
if command -v xclip >/dev/null 2>&1; then
	printf '#%s' "${hex}" | xclip -selection clipboard 2>/dev/null &&
		say "Copied #${hex} to the clipboard" 2500 0
fi
say "Colour #${hex} (clipboard unavailable)" 3000 1
PICK
	chmod 755 "${pck}"
	register_file "${pck}"
	return 0
}

# ---------------------------------------------------------------------
#  Lock screen, idle handling and power menu (X11)
# ---------------------------------------------------------------------
write_lock_and_power() {
	# i3lock takes a PNG or a flat colour. The wallpaper as the lock screen
	# is what the reference shows, so prefer it; fall back to the flat
	# Everforest background when there is no wallpaper yet.
	local lock="/usr/local/bin/i3-everforest-lock"
	cat >"${lock}" <<'LOCK'
#!/bin/sh
# Lock the X session.
#
# i3lock cannot scale a JPEG, so the wallpaper is converted to a PNG that
# matches the current screen size and cached next to it. A flat Everforest
# background is the fallback, so the lock screen never comes up white.
wall="${XDG_DATA_HOME:-$HOME/.local/share}/i3-everforest/wallpaper.jpg"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/i3-everforest/lock.png"

# Already locked? i3lock refuses a second instance, which is fine.
pgrep -x i3lock >/dev/null 2>&1 && exit 0

if [ -f "${wall}" ]; then
	mkdir -p "$(dirname "${cache}")" 2>/dev/null
	if [ ! -s "${cache}" ] || [ "${wall}" -nt "${cache}" ]; then
		# i3lock needs a PNG at (close to) the screen size. Asking X for the
		# dimensions can fail; an empty argument would make convert error out
		# and the lock screen fall back to a flat colour, so it is checked.
		dims=""
		if command -v xdpyinfo >/dev/null 2>&1; then
			dims=$(xdpyinfo 2>/dev/null |
				awk '/dimensions:/{split($2,a,"x"); if (a[1] && a[2]) print a[1]"x"a[2]; exit}')
		fi
		[ -n "${dims}" ] || dims="1920x1080"
		if command -v convert >/dev/null 2>&1; then
			# Fit the wallpaper to the screen, then dim it so the indicator
			# stays readable over a bright image. -modulate is
			# brightness,saturation,hue - the dimming goes in the *first*
			# component; using the third would rotate the hue instead and
			# turned the lock screen magenta.
			convert "${wall}" -resize "${dims}" -modulate 55,100,100 "${cache}" \
				>/dev/null 2>&1 || rm -f "${cache}"
		fi
	fi
fi

# Load the palette written by the installer, then hand over to i3lock.
icons="$HOME/.config/i3/i3lock-color.xresources"
if [ -f "${icons}" ] && command -v xrdb >/dev/null 2>&1; then
	xrdb -merge "${icons}" >/dev/null 2>&1 || true
fi

lock() {
	if [ -s "${cache}" ]; then
		i3lock -n -i "${cache}" -e -f
	else
		i3lock -n -c 1e2326 -e -f
	fi
}

lock
exit 0
LOCK
	chmod 755 "${lock}"
	register_file "${lock}"

	# Idle handling: DISABLED (2026-11-03). The session does not lock, blank or
	# sleep on its own; the screen is kept on. i3-everforest-lock still runs on
	# $mod+Escape, so manual locking keeps working.
	# Original behaviour (lock at 10 min, blank at 15 min, lock on resume) is
	# preserved as a commented block at the end of the generated script.
	local idle="/usr/local/bin/i3-everforest-idle"
	cat >"${idle}" <<'IDLE'
#!/bin/sh
# Idle handling — DISABLED at the user's request (2026-11-03).
#
# Previously this script started xss-lock (lock before suspend) and enforced
# two idle stages with xprintidle: lock at 600s, DPMS power-off at 900s.
# All of that is gone: the session no longer locks itself, no longer blanks,
# and no longer sleeps. The screen is kept on unconditionally.
#
# Manual locking still works: $mod+Escape runs i3-everforest-lock.
# To restore the old behaviour, reinstall i3-everforest or see the commented
# block at the bottom of this file.

if command -v xset >/dev/null 2>&1; then
	# No X screensaver blanking.
	xset s off >/dev/null 2>&1
	xset s noblank >/dev/null 2>&1
	# Power the display back on first, in case a previous session left it in a
	# DPMS-off state, and only then disable DPMS. Order matters: `xset dpms
	# force on` re-arms DPMS, so a `-dpms` issued before it gets undone and the
	# monitor would blank again once the timeout elapsed.
	xset dpms 0 0 0 >/dev/null 2>&1
	xset dpms force on >/dev/null 2>&1
	xset -dpms >/dev/null 2>&1
fi

# Hard-block suspend/hibernate for the lifetime of this session, so nothing
# (suspend key, logind idle policy, the power menu, another user's command)
# can put the machine to sleep. The lock is released automatically at logout.
if command -v systemd-inhibit >/dev/null 2>&1; then
	# i3 restart re-runs this script while the previous inhibitor is still
	# alive; skip instead of stacking a second identical lock.
	if pgrep -f "systemd-inhibit.*--who=i3-everforest" >/dev/null 2>&1; then
		exit 0
	fi
	exec systemd-inhibit \
		--what=sleep \
		--who=i3-everforest \
		--why="Suspend disabled: screen kept on" \
		--mode=block \
		sleep infinity
fi

exit 0

# ---------------------------------------------------------------------------
# Old behaviour, kept for reference:
#
# if command -v xss-lock >/dev/null 2>&1; then
# 	xss-lock --transfer-sleep-lock -- "${lockcmd}" >/dev/null 2>&1 &
# fi
# xset s 600 600
# xset dpms 900 900 900
# ... plus the xprintidle loop that ran the locker at 600s and
# `xset dpms force off` at 900s.
# ---------------------------------------------------------------------------
IDLE
	chmod 755 "${idle}"
	register_file "${idle}"

	# Power menu: rofi list -> real actions. Session-scoped only when the
	# systemd logind interface is there, and it asks before shutting down.
	local pwr="/usr/local/bin/i3-everforest-powermenu"

	# The reference uses wlogout for this, which is Wayland-only (it links
	# gtk-layer-shell). The replacement paints the same full-screen grid with
	# plain GTK: a dark scrim, one large tile per action, Esc to dismiss.
	cat >/usr/local/bin/i3-everforest-powermenu-ui <<'PWRUI'
#!/usr/bin/env python3
"""Full-screen power menu (wlogout look) for X11."""
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
    ("Lock", "\uf023", ["/usr/local/bin/i3-everforest-lock"]),
    ("Log out", "\uf2f5", ["i3-msg", "exit"]),
    ("Suspend", "\uf186", ["sh", "-c",
                            "/usr/local/bin/i3-everforest-lock; "
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
    win.fullscreen()

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
	chmod 755 /usr/local/bin/i3-everforest-powermenu-ui
	register_file /usr/local/bin/i3-everforest-powermenu-ui

	cat >"${pwr}" <<'PWR'
#!/bin/sh
# Power menu for the bar's red button and for Mod+Shift+E.
#
# wlogout (the reference's power menu) is Wayland-only, so this launches the
# GTK equivalent, which draws the same full-screen grid on X11.
export LC_ALL=C

exec /usr/local/bin/i3-everforest-powermenu-ui
PWR
	chmod 755 "${pwr}"
	register_file "${pwr}"
	return 0
}


write_bash_extras() {
	local rc="${HOME_DIR}/.bashrc"
	local marker_begin="# >>> i3-everforest >>>"
	local marker_end="# <<< i3-everforest <<<"

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
# Everforest prompt (i3 rice) - remove by running the installer --uninstall
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
