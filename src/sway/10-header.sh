#!/usr/bin/env bash
# =====================================================================
#  Sway Everforest Installer for Debian 13 (trixie)
# ---------------------------------------------------------------------
#  Reproduces this rice on a clean Debian 13 install:
#    Theme   : Everforest-Dark-BL-LB  (Fausto-Korpsvart / Everforest)
#    Icons   : Material-Black-Lime-Numix-FLAT
#    Terminal: foot                   Bar     : C bar (native Wayland)
#    Launcher: Wofi                   Files   : Nemo
#    Wallpaper: wallhaven.cc/w/4xxw9z
#
#  Usage:
#    sudo ./sway-everforest-installer.sh            # interactive TUI
#    ./sway-everforest-installer.sh --yes           # accept defaults
#    ./sway-everforest-installer.sh --uninstall
#
#  Everything this script creates is recorded in a manifest so that
#  "--uninstall" restores your machine to its previous state.
# =====================================================================

set -Eeuo pipefail
shopt -s nullglob extglob

VERSION="1.0.0"
PROG="sway-everforest"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------
SHARE_DIR_NAME="sway-everforest"
THEME_NAME="Everforest-Dark-BL-LB"
ICON_NAME="Material-Black-Lime-Numix-FLAT"
SESSION_FILE="sway-everforest.desktop"

WALLPAPER_URL="https://w.wallhaven.cc/full/4x/wallhaven-4xxw9z.jpg"
THEME_SRC_URL="https://codeload.github.com/Fausto-Korpsvart/Everforest-GTK-Theme/tar.gz/refs/heads/master"
ICON_SRC_URL="https://codeload.github.com/razorhavoc/HTB-pwnbox/tar.gz/refs/heads/master"
ICON_SRC_PATH="usr/share/icons/${ICON_NAME}"

# ---------------------------------------------------------------------
# Everforest palette (used by the TUI itself)
# ---------------------------------------------------------------------
EF_BG0="30;35;38"       # #1e2326
EF_BG1="39;46;51"       # #272e33
EF_BG2="47;51;54"       # #2f3336
EF_FG="211;198;170"     # #d3c6aa
EF_LIME="185;255;102"   # #b9ff66
EF_GREEN="167;192;128"  # #a7c080
EF_BLUE="127;187;179"   # #7fbbb3
EF_YELLOW="219;188;127" # #dbbc7f
EF_RED="230;126;128"    # #e67e80
EF_GREY="122;132;120"   # #7a8478

# ---------------------------------------------------------------------
# Options (defaults)
# ---------------------------------------------------------------------
OPT_YES=0
OPT_UNINSTALL=0
OPT_DRY_RUN=0
OPT_KEEP_PACKAGES=0
OPT_PURGE_EVERYTHING=0
OPT_USER=""
OPT_APT_UPDATE=1
OPT_ASSUME_TUI="auto"

CORE=1        # desktop packages (sway, waybar, alacritty, wofi, ...)
APPS=1        # file manager, system monitor, media, power menu, ...
GTK_THEME=1   # Everforest GTK theme + GTK3/GTK4/libadwaita settings
ICONS=1       # Material-Black-Lime-Numix-FLAT icon theme
WALLPAPER=1   # wallpaper
DOTS=1        # sway/waybar/alacritty/wofi/mako/swaylock/btop configs
SESSION=1     # wayland-sessions entry (login from a display manager)
SHELLFX=1     # "mf" fetch script + Everforest bash prompt
SDDM=1        # SDDM display manager + SilentSDDM theme

# Waybar transparency: solid (opaque), soft, clear. Applied to the panel and
# the pills together so the bar reads as one material.
BAR_OPACITY="solid"

TARGET_USER=""
TARGET_GROUP=""
HOME_DIR=""
STATE_DIR=""
BACKUP_DIR=""
MANIFEST=""
TMPWORK=""
LOG_FILE=""
SPIN_PID=""
ASSET_DIR=""
SCRIPT_ASSET_DIR=""

# Runtime
INTERACTIVE=0
TUI_LINES=24
TUI_COLS=80

# ---------------------------------------------------------------------
# Terminal / colour helpers
# ---------------------------------------------------------------------
setup_colors() {
	if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
		C_RESET="" C_FG="" C_LIME="" C_GREEN="" C_BLUE="" C_YELLOW="" C_RED="" C_GREY="" C_BG="" C_BOLD=""
		return 0
	fi
	C_RESET=$'\033[0m' C_BOLD=$'\033[1m'
	C_FG=$'\033[38;2;'"${EF_FG}"'m'
	C_LIME=$'\033[38;2;'"${EF_LIME}"'m'
	C_GREEN=$'\033[38;2;'"${EF_GREEN}"'m'
	C_BLUE=$'\033[38;2;'"${EF_BLUE}"'m'
	C_YELLOW=$'\033[38;2;'"${EF_YELLOW}"'m'
	C_RED=$'\033[38;2;'"${EF_RED}"'m'
	C_GREY=$'\033[38;2;'"${EF_GREY}"'m'
	C_BG=$'\033[48;2;'"${EF_BG1}"'m'
}

ui_clear() { [[ ${INTERACTIVE} -eq 1 ]] && printf '\033[H\033[2J'; }

ui_hdr() {
	printf '\n%s%s  %s%s\n' "${C_BOLD}" "${C_LIME}" "$*" "${C_RESET}"
	printf '%s  %s%s\n' "${C_GREY}" "────────────────────────────────────────────────────────────" "${C_RESET}"
}

ui_line() { printf '  %s\n' "$*"; }
ui_dim()  { printf '  %s%s%s\n' "${C_GREY}" "$*" "${C_RESET}"; }
ui_step() { printf '  %s❯%s %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
ui_ok()   { printf '  %s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
ui_warn() { printf '  %s!%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
ui_err()  { printf '  %s✘%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
ui_rule() { printf '  %s%s%s\n' "${C_GREY}" "────────────────────────────────────────────────────────────" "${C_RESET}"; }

die() {
	ui_err "$*"
	if [[ -n "${LOG_FILE}" && -s "${LOG_FILE}" ]]; then
		printf '\n'; ui_dim "Last 20 log lines (${LOG_FILE}):"
		tail -n 20 "${LOG_FILE}" | sed 's/^/    /'
	fi
	exit 1
}

cleanup() {
	if [[ -n "${SPIN_PID}" ]] && kill -0 "${SPIN_PID}" 2>/dev/null; then
		kill "${SPIN_PID}" 2>/dev/null || true
		wait "${SPIN_PID}" 2>/dev/null || true
	fi
	if [[ -n "${TMPWORK}" && -d "${TMPWORK}" && -z "${KEEP_TMP:-}" ]]; then
		rm -rf "${TMPWORK}" 2>/dev/null || true
	fi
	# restore the cursor only if the TUI actually hid it
	if [[ ${INTERACTIVE:-0} -eq 1 && -t 1 ]]; then
		printf '\033[?25h' 2>/dev/null || true
	fi
}
trap cleanup EXIT
trap 'die "unexpected failure at line ${LINENO}"' ERR

# ---------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

mul() { # print n copies of a character
	local n="$1" ch="$2" out="" i
	for ((i = 0; i < n; i++)); do out+="${ch}"; done
	printf '%s' "${out}"
}

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }

apt_cleanup_name() { printf '%s' "${1%%:*}"; }

# ---------------------------------------------------------------------
