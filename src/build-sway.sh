#!/usr/bin/env bash
# =====================================================================
#  build-sway.sh - assemble the single-file Sway installer from
#  src-sway/*.sh plus the asset payload.
#
#  This is the sibling of build-i3.sh (which builds the i3 installer).
#  Both read the same assets/ tree; each keeps its own source directory
#  so the two rices can evolve independently.
#
#  Run from anywhere:            src/build-sway.sh
#  Output:                       sway-setup.sh in the project root
# =====================================================================
set -Eeuo pipefail

# This script lives in src/, so the project root is its parent. Anchoring on the
# root rather than the script directory keeps the installer, the staging
# directory and assets/ in one predictable place no matter where the script is
# invoked from.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="sway-setup.sh"
SRC="src/sway"
BUILD=".build-sway"
ASSETS="assets"

THEME_NAME="Everforest-Dark-BL-LB"
ICON_NAME="Material-Black-Lime-Numix-FLAT"

rm -rf "$BUILD"
mkdir -p "$BUILD/payload"

echo "==> collecting assets"

# ---- icons ----------------------------------------------------------
ICONS_SRC="${ICONS_SRC:-}"
if [[ -z "$ICONS_SRC" ]]; then
	for c in "$ASSETS/icons/$ICON_NAME" /tmp/pwnbox/usr/share/icons/"$ICON_NAME"; do
		[[ -d "$c" ]] && { ICONS_SRC="$c"; break; }
	done
fi
if [[ -n "$ICONS_SRC" && -d "$ICONS_SRC" ]]; then
	tar -C "$(dirname "$ICONS_SRC")" -cf - "$(basename "$ICONS_SRC")" | xz -T0 -9e >"$BUILD/payload/icons.tar.xz"
	echo "    icons      $(du -h "$BUILD/payload/icons.tar.xz" | cut -f1)"
else
	echo "    icons      MISSING (will be downloaded at install time)"
fi

# ---- GTK theme ------------------------------------------------------
THEME_SRC="${THEME_SRC:-$ASSETS/gtk-theme/$THEME_NAME}"
if [[ -d "$THEME_SRC" ]]; then
	tar -C "$(dirname "$THEME_SRC")" -cf - "$(basename "$THEME_SRC")" | xz -T0 -9e >"$BUILD/payload/gtk-theme.tar.xz"
	echo "    gtk-theme  $(du -h "$BUILD/payload/gtk-theme.tar.xz" | cut -f1)"
else
	echo "    gtk-theme  MISSING (will be downloaded at install time)"
fi

# ---- wallpaper ------------------------------------------------------
if [[ -f "$ASSETS/wallpaper.jpg" ]]; then
	xz -T0 -9e -c "$ASSETS/wallpaper.jpg" >"$BUILD/payload/wallpaper.jpg.xz"
	echo "    wallpaper  $(du -h "$BUILD/payload/wallpaper.jpg.xz" | cut -f1)"
else
	echo "    wallpaper  MISSING (will be downloaded at install time)"
fi

# ---- fonts ----------------------------------------------------------
if [[ -d "$ASSETS/fonts" ]]; then
	tar -C "$ASSETS" -cf - fonts | xz -T0 -9e >"$BUILD/payload/fonts.tar.xz"
	echo "    fonts      $(du -h "$BUILD/payload/fonts.tar.xz" | cut -f1)"
else
	echo "    fonts      MISSING (bar icons may show as boxes)"
fi

# ---- SDDM theme -----------------------------------------------------
if [[ -d "$ASSETS/sddm/silent" ]]; then
	tar -C "$ASSETS/sddm" -cf - silent | xz -T0 -9e >"$BUILD/payload/sddm-theme.tar.xz"
	echo "    sddm       $(du -h "$BUILD/payload/sddm-theme.tar.xz" | cut -f1)"
else
	echo "    sddm       MISSING (stock theme will be used)"
fi

# ---- C bar (native Wayland) -----------------------------------------
BAR_WL_SRC="${BAR_WL_SRC:-$ASSETS/bar-sway}"
if [[ -d "$BAR_WL_SRC" ]]; then
	# Ship the sources, not a binary: the installer compiles them on the target
	# so the result matches that machine's libwayland/cairo versions.
	(cd "$(dirname "$BAR_WL_SRC")" && tar -cf - \
		--exclude='*.o' --exclude='i3-everforest-bar-wl' \
		"$(basename "$BAR_WL_SRC")") | xz -T0 -9e >"$BUILD/payload/bar-wl.tar.xz"
	echo "    bar-wl     $(du -h "$BUILD/payload/bar-wl.tar.xz" | cut -f1)"
else
	echo "    bar-wl     MISSING (waybar will be used)"
fi

# ---- sanity ---------------------------------------------------------
for f in "$SRC"/10-header.sh "$SRC"/90-main.sh; do
	[[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done

# The payload marker string in 85-payload.sh must match what we append.
MARKER="$(sed -n 's/^PAYLOAD_MARKER="\(.*\)"$/\1/p' "$SRC/85-payload.sh")"
[[ -n "$MARKER" ]] || { echo "no PAYLOAD_MARKER in src-sway/85-payload.sh" >&2; exit 1; }

echo "==> assembling $OUT"
{
	cat "$SRC"/10-header.sh
	for f in "$SRC"/20-*.sh "$SRC"/30-*.sh "$SRC"/40-*.sh "$SRC"/5*.sh "$SRC"/6*.sh "$SRC"/70-*.sh "$SRC"/75-*.sh "$SRC"/77-*.sh "$SRC"/80-*.sh "$SRC"/85-*.sh "$SRC"/90-*.sh; do
		[[ -f "$f" ]] || continue
		printf '\n# ---------------------------------------------------------------------\n# %s\n# ---------------------------------------------------------------------\n' "$(basename "$f")"
		cat "$f"
	done
} >"$OUT.tmp"

chmod +x "$OUT.tmp"

# ---- payload --------------------------------------------------------
{
	printf '\n\n# %s\n' "$MARKER"
	printf '# Assets below are base64-encoded archives. Do not edit by hand.\n'
	for a in icons.tar.xz gtk-theme.tar.xz wallpaper.jpg.xz sddm-theme.tar.xz fonts.tar.xz bar-wl.tar.xz; do
		[[ -f "$BUILD/payload/$a" ]] || continue
		printf '\n@@asset %s.b64\n' "$a"
		base64 -w 76 "$BUILD/payload/$a"
		printf '@@end\n'
	done
} >>"$OUT.tmp"

mv "$OUT.tmp" "$OUT"
chmod +x "$OUT"

echo "==> done"
ls -lh "$OUT"
printf '    lines: %s   sha256: %s\n' "$(wc -l <"$OUT")" "$(sha256sum "$OUT" | cut -d' ' -f1)"
