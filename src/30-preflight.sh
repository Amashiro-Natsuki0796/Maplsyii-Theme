# =====================================================================
#  Pre-flight checks
# =====================================================================

check_root() {
	[[ "${EUID}" -eq 0 ]] || die "run this installer as root:  sudo $0"
}

check_distro() {
	local id="" ver=""
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		id="${ID:-}"; ver="${VERSION_ID:-}"
	fi
	[[ "${id}" == "debian" ]] || die "this installer targets Debian 13 (trixie); detected '${id:-unknown}'"
	case "${ver}" in
	13*) : ;;
	*) ui_warn "Debian ${ver} detected - tested on Debian 13 (trixie) only" ;;
	esac
}

check_arch_packages() {
	# wayland stack is amd64/arm64 only in Debian; refuse on 32-bit
	local arch; arch="$(dpkg --print-architecture)"
	case "${arch}" in
	amd64|arm64) : ;;
	*) die "unsupported architecture '${arch}' (need amd64 or arm64)" ;;
	esac
}

check_systemd() {
	[[ -d /run/systemd/system ]] || ui_warn "systemd not detected; some services will not be enabled"
}

resolve_target_user() {
	if [[ -n "${OPT_USER}" ]]; then
		TARGET_USER="${OPT_USER}"
	elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
		TARGET_USER="${SUDO_USER}"
	elif [[ -n "${PKEXEC_UID:-}" ]]; then
		TARGET_USER="$(getent passwd "${PKEXEC_UID}" | cut -d: -f1)"
	elif [[ -n "${DOAS_USER:-}" ]]; then
		TARGET_USER="${DOAS_USER}"
	else
		TARGET_USER="$(logname 2>/dev/null || true)"
	fi
	if [[ -z "${TARGET_USER}" ]]; then TARGET_USER="${FALLBACK_USER:-builder}"; fi

	if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
		# fall back to the first normal user
		TARGET_USER="$(awk -F: '($3>=1000 && $3<65000 && $1!="nobody"){print $1; exit}' /etc/passwd)"
	fi
	id -u "${TARGET_USER}" >/dev/null 2>&1 || die "cannot determine the desktop user; re-run with --user <name>"
	if [[ "${TARGET_USER}" == "root" ]]; then die "refusing to install a desktop session for root; use --user <name>"; fi

	TARGET_GROUP="$(id -gn "${TARGET_USER}")"
	HOME_DIR="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
	if [[ -z "${HOME_DIR}" || ! -d "${HOME_DIR}" ]]; then die "home directory for '${TARGET_USER}' does not exist"; fi

	STATE_DIR="${HOME_DIR}/.local/state/${SHARE_DIR_NAME}"
	BACKUP_DIR="${STATE_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
	MANIFEST="${STATE_DIR}/manifest.list"
	LOG_FILE="${STATE_DIR}/install.log"
}

as_user() {
	# runuser keeps root's environment by default, which would make tools
	# like gsettings write into /root. Re-export the user's XDG paths.
	runuser -u "${TARGET_USER}" -- env \
		HOME="${HOME_DIR}" \
		USER="${TARGET_USER}" \
		LOGNAME="${TARGET_USER}" \
		XDG_CONFIG_HOME="${HOME_DIR}/.config" \
		XDG_DATA_HOME="${HOME_DIR}/.local/share" \
		XDG_STATE_HOME="${HOME_DIR}/.local/state" \
		XDG_CACHE_HOME="${HOME_DIR}/.cache" \
		"$@"
}
chown_user() { chown -R "${TARGET_USER}:${TARGET_GROUP}" "$@"; }

preflight() {
	ui_hdr "Pre-flight checks"
	check_root
	check_distro
	check_arch_packages
	check_systemd
	resolve_target_user
	ui_ok "distribution : Debian $(. /etc/os-release; echo "${VERSION_ID}") ($(dpkg --print-architecture))"
	ui_ok "desktop user : ${TARGET_USER} (${HOME_DIR})"
	ui_ok "state        : ${STATE_DIR}"

	# A dry run must not create the state directory, the log or the manifest.
	if [[ "${OPT_DRY_RUN}" -eq 1 ]]; then
		return 0
	fi

	mkdir -p "${STATE_DIR}/backups"
	touch "${LOG_FILE}"
	chown_user "${STATE_DIR}"
	: > "${MANIFEST}.new"

	# Keep apt usable on a live system while we work.
	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none
	export NEEDRESTART_MODE=a
	if [[ -f /etc/needrestart/needrestart.conf ]]; then
		export NEEDRESTART_SUSPEND=1
	fi
}

# ---------------------------------------------------------------------
# Manifest - every change is recorded so --uninstall can undo it
# ---------------------------------------------------------------------
manifest_add() {
	[[ -n "${MANIFEST}" ]] || return 0
	printf '%s\t%s\n' "$1" "$2" >>"${MANIFEST}.new"
}

manifest_pkg() { manifest_add "pkg" "$1"; }
manifest_file() { manifest_add "file" "$1"; }
manifest_dir() { manifest_add "dir" "$1"; }
manifest_backup() { manifest_add "backup" "$1"; }

# Register a file we are about to create/overwrite.
register_file() {
	local path="$1"
	manifest_file "${path}"
	printf '%s\n' "${path}" >>"${STATE_DIR}/installed-files.list"
}

# Back up an existing file/dir before we overwrite it.
# The *first* backup of a path wins: if the installer is run again, later
# runs must not replace the record of what the file looked like before the
# very first install, or uninstall would restore an intermediate state.
backup_path() {
	local path="$1" rel dest map
	[[ -e "${path}" || -L "${path}" ]] || return 0
	map="${STATE_DIR}/backup-map.tsv"
	mkdir -p "${STATE_DIR}"
	[[ -f "${map}" ]] || : >"${map}"

	# already recorded and still present? nothing to do
	if [[ -f "${map}" ]]; then
		local existing
		existing="$(awk -F'\t' -v p="${path}" '$1 == p { print $2; exit }' "${map}")"
		if [[ -n "${existing}" && -e "${existing}" ]]; then
			return 0
		fi
	fi

	rel="${path#/}"
	dest="${BACKUP_DIR}/${rel}"
	mkdir -p "$(dirname "${dest}")"
	cp -a "${path}" "${dest}"
	manifest_backup "${path}"
	printf '%s\t%s\n' "${path}" "${dest}" >>"${map}"
}
