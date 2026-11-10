# =====================================================================
#  GPU: driver parameters and clock policy
# =====================================================================
#
# Two independent problems are solved here, both specific to this rice's
# target hardware (AMD Kaveri, the CIK-generation APU), but written so that
# machines which do not need them are left untouched.
#
#   1. DRM atomic modesetting.
#      The Wayland greeter (see 77-sddm.sh) runs under weston, and weston 16
#      refuses to start without atomic modesetting. Kaveri's default driver is
#      radeon, which has no atomic support; amdgpu does, but only with Display
#      Core forced on. So the kernel command line gets
#          radeon.cik_support=0 amdgpu.cik_support=1 amdgpu.dc=1
#      This is applied only when the GPU is actually a CIK part; on newer AMD
#      hardware amdgpu is already the default and the parameters are noise.
#
#   2. GPU clock policy.
#      amdgpu on CIK initialises DPM but never exports the frequency tables
#      (pp_dpm_sclk is empty), so the governor cannot select a state on demand:
#      the GPU jumps to ~520 MHz for a moment under load and falls straight
#      back to the 354 MHz floor. Pinning the performance level keeps it at its
#      top state (~910 MHz) instead.
#
# Both changes are reversible: grub.cfg is regenerated from a backup, and the
# clock service is a single unit that can be disabled.

GPU_SERVICE="/etc/systemd/system/amdgpu-performance.service"

# Is the display GPU a CIK part that radeon currently owns?
#
# Matched by PCI vendor plus the driver in use, not by marketing name: the
# point is to change the kernel command line only where it is needed.
gpu_is_cik_on_radeon() {
	local drv

	# The VGA controller, not the secondary compute card.
	for d in /sys/bus/pci/devices/*; do
		[[ -r "$d/class" ]] || continue
		# class 0x0300xx is a display controller; 0x0302xx is 3D-only.
		read -r cls <"$d/class" || continue
		[[ "$cls" == 0x0300* ]] || continue

		[[ -r "$d/vendor" ]] || continue
		read -r vend <"$d/vendor" || continue
		[[ "$vend" == "0x1002" ]] || continue        # AMD

		drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
		[[ "$drv" == "radeon" ]] && return 0
	done
	return 1
}


gpu_write_clock_service() {
	if ! gpu_is_cik_on_radeon && [[ ! -d /sys/module/amdgpu ]]; then
		ui_dim "amdgpu not in use; clock service not installed"
		return 0
	fi

	if [[ ${OPT_DRY_RUN} -eq 1 ]]; then
		ui_dim "would install ${GPU_SERVICE}"
		return 0
	fi

	cat >"${GPU_SERVICE}" <<'EOF'
# Pin the GPU to its highest clock state.
#
# amdgpu on CIK (Kaveri) initialises DPM but never exports the frequency tables
# (pp_dpm_sclk/pp_dpm_mclk are empty), so the governor cannot pick a state on
# demand: the GPU jumps to ~520 MHz for an instant under load and falls back to
# the 354 MHz floor. Games therefore run at roughly half speed.
#
# Forcing the performance level works around the missing tables by keeping the
# hardware at its top state (~910 MHz) permanently.
#
# Cost: the GPU no longer idles down, so it draws its full power and runs hot
# all the time. That is the trade accepted for working 3D performance. Disable
# with: systemctl disable --now amdgpu-performance
[Unit]
Description=Pin the AMD GPU to high performance
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c "for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do [ -w \"$f\" ] && echo high > \"$f\"; done"

[Install]
WantedBy=multi-user.target
EOF

	chmod 644 "${GPU_SERVICE}"
	register_file "${GPU_SERVICE}"
	systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
	systemctl enable amdgpu-performance.service >>"${LOG_FILE}" 2>&1 || {
		ui_warn "could not enable the GPU clock service"
		return 1
	}
	ui_ok "GPU pinned to high performance (${GPU_SERVICE})"
	return 0
}

# Launching a game from the menu must not pick the wrong GPU.
#
# SuperTuxKart ships PrefersNonDefaultGPU=true. Launchers honour that by setting
# DRI_PRIME=1, which points at the *second* GPU. On a machine whose second GPU
# is an NVIDIA card with no display output, Mesa cannot use it and falls back to
# llvmpipe - software rendering, single-digit fps - while the same game started
# from a terminal runs fine on the AMD GPU's hardware acceleration.
#
# The override goes in ~/.local/share/applications so the packaged .desktop file
# stays untouched and removing the file undoes the fix.
gpu_fix_desktop_entries() {
	[[ ${OPT_DRY_RUN} -eq 1 ]] && {
		ui_dim "would drop PrefersNonDefaultGPU from game .desktop files"
		return 0
	}

	local src dst fixed=0
	for src in /usr/share/applications/supertuxkart.desktop; do
		[[ -f "$src" ]] || continue
		grep -q '^PrefersNonDefaultGPU' "$src" || continue

		dst="${HOME_DIR}/.local/share/applications/$(basename "$src")"
		install -d "$(dirname "$dst")"
		grep -v '^PrefersNonDefaultGPU' "$src" >"$dst"
		chown_user "$dst" 2>/dev/null || true
		register_file "$dst"
		fixed=$((fixed + 1))
	done

	if [[ $fixed -gt 0 ]]; then
		command -v update-desktop-database >/dev/null 2>&1 &&
			update-desktop-database "${HOME_DIR}/.local/share/applications" \
				>>"${LOG_FILE}" 2>&1 || true
		ui_ok "removed PrefersNonDefaultGPU from ${fixed} launcher entry/entries"
	else
		ui_dim "no launcher entries needed the GPU preference fix"
	fi
	return 0
}

install_gpu() {
	ui_step "GPU configuration"

	# The kernel command line is NOT touched here on purpose.
	#
	# Switching radeon -> amdgpu is a boot-level change: if amdgpu cannot drive
	# the panel on this particular machine, the next boot has no display at all,
	# and that is not something an installer should risk on the user's behalf.
	# It stays available as a separate, explicit repair tool:
	#     sway-everforest-fix-grub
	# which the installer drops next to the other helpers.
	ui_dim "kernel driver selection left to sway-everforest-fix-grub"

	gpu_write_clock_service || true
	gpu_fix_desktop_entries || true
	return 0
}
