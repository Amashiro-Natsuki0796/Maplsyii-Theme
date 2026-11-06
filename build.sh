#!/usr/bin/env bash
# =====================================================================
#  build.sh - assemble the single-file installer from src/*.sh plus the
#  asset payload (icons, GTK theme, wallpaper, fonts, SDDM theme).
#
#  Run from the project root:   ./build.sh
#  Output:                      ./i3-everforest-installer.sh
# =====================================================================
set -Eeuo pipefail
cd "$(dirname "$0")"

OUT="i3-everforest-installer.sh"
SRC="src"
BUILD=".build"
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
[[ -d "$ICONS_SRC" ]] || { echo "!! icon theme not found (set ICONS_SRC)"; exit 1; }
echo "    icons: $ICONS_SRC"
tar -C "$(dirname "$ICONS_SRC")" -cf - "$ICON_NAME" | xz -T0 -9e >"$BUILD/payload/icons.tar.xz"

# ---- gtk theme ------------------------------------------------------
THEME_SRC="${THEME_SRC:-}"
if [[ -z "$THEME_SRC" ]]; then
	for c in "$ASSETS/gtk-theme/$THEME_NAME" "/usr/share/themes/$THEME_NAME"; do
		[[ -d "$c" ]] && { THEME_SRC="$c"; break; }
	done
fi
[[ -d "$THEME_SRC" ]] || { echo "!! gtk theme not found (set THEME_SRC)"; exit 1; }
echo "    theme: $THEME_SRC"
tar -C "$(dirname "$THEME_SRC")" -cf - "$THEME_NAME" | xz -T0 -9e >"$BUILD/payload/gtk-theme.tar.xz"

# ---- wallpaper ------------------------------------------------------
WALL_SRC="${WALL_SRC:-$ASSETS/wallpaper.jpg}"
[[ -f "$WALL_SRC" ]] || WALL_SRC="/tmp/shot1.jpg"
[[ -f "$WALL_SRC" ]] || { echo "!! wallpaper not found (set WALL_SRC)"; exit 1; }
echo "    wallpaper: $WALL_SRC"
xz -T0 -9e -c "$WALL_SRC" >"$BUILD/payload/wallpaper.jpg.xz"

# ---- user avatar (shown on the SDDM login screen) -------------------
AVATAR_SRC="${AVATAR_SRC:-$ASSETS/user-avatar.jpg}"
if [[ -f "$AVATAR_SRC" ]]; then
	echo "    avatar: $AVATAR_SRC"
	cp -f "$AVATAR_SRC" "$BUILD/payload/user-avatar.jpg"
else
	echo "!! avatar not found at $AVATAR_SRC (set AVATAR_SRC)"
	exit 1
fi

# ---- sddm theme (SilentSDDM, pruned to static runtime files) --------
SDDM_SRC="${SDDM_SRC:-$ASSETS/sddm/silent}"
if [[ -d "$SDDM_SRC" ]]; then
	echo "    sddm theme: $SDDM_SRC"
	tar -C "$(dirname "$SDDM_SRC")" -cf - "$(basename "$SDDM_SRC")" | xz -T0 -9e >"$BUILD/payload/sddm-theme.tar.xz"
else
	echo "!! SilentSDDM theme not found at $SDDM_SRC (set SDDM_SRC)"
	exit 1
fi

# ---- nerd font (symbols used by the bar and the prompt) --------------
FONT_SRC="${FONT_SRC:-$ASSETS/fonts}"
if [[ -d "$FONT_SRC" ]]; then
	echo "    fonts: $FONT_SRC"
	tar -C "$FONT_SRC" -cf - . | xz -T0 -9e >"$BUILD/payload/fonts.tar.xz"
else
	echo "!! fonts dir not found at $FONT_SRC (set FONT_SRC)"
	exit 1
fi

# ---- bar config (opacity preset, module order) ----------------------
BAR_SRC="${BAR_SRC:-$ASSETS/bar}"
if [[ -d "$BAR_SRC" ]]; then
	echo "    bar config: $BAR_SRC"
	tar -C "$(dirname "$BAR_SRC")" -cf - "$(basename "$BAR_SRC")" | xz -T0 -9e >"$BUILD/payload/bar.tar.xz"
else
	echo "!! bar config not found at $BAR_SRC (set BAR_SRC)"
	exit 1
fi

# ---- bar sources (C, compiled at install time) ----------------------
BAR_C_SRC="${BAR_C_SRC:-$ASSETS/bar-c}"
if [[ -d "$BAR_C_SRC" ]]; then
	echo "    bar sources: $BAR_C_SRC"
	tar -C "$(dirname "$BAR_C_SRC")" -cf - "$(basename "$BAR_C_SRC")" | xz -T0 -9e >"$BUILD/payload/bar-c.tar.xz"
else
	echo "!! bar sources not found at $BAR_C_SRC (set BAR_C_SRC)"
	exit 1
fi

# ---- st patches (scrollback, wheel, Ctrl+click URLs) -----------------
ST_PATCHES_SRC="${ST_PATCHES_SRC:-$ASSETS/st-patches}"
if [[ -d "$ST_PATCHES_SRC" ]]; then
	echo "    st patches: $ST_PATCHES_SRC"
	for p in scrollback mouse url scrollbar; do
		[[ -f "$ST_PATCHES_SRC/$p.diff" ]] || {
			echo "!! missing st patch $p.diff"
			exit 1
		}
	done
	tar -C "$(dirname "$ST_PATCHES_SRC")" -cf - "$(basename "$ST_PATCHES_SRC")" | xz -T0 -9e >"$BUILD/payload/st-patches.tar.xz"
else
	echo "!! st patches not found at $ST_PATCHES_SRC"
	exit 1
fi

# ---- assemble -------------------------------------------------------
echo "==> assembling $OUT"
{
	cat "$SRC"/10-header.sh
	for f in "$SRC"/20-*.sh "$SRC"/30-*.sh "$SRC"/40-*.sh "$SRC"/5*.sh "$SRC"/6*.sh "$SRC"/70-*.sh "$SRC"/75-*.sh "$SRC"/77-*.sh "$SRC"/80-*.sh "$SRC"/85-*.sh "$SRC"/90-*.sh; do
		[[ -f "$f" ]] || continue
		printf '\n# ---------------------------------------------------------------------\n# %s\n# ---------------------------------------------------------------------\n' "$(basename "$f")"
		cat "$f"
	done
	# main "$@" is already the last statement of 90-main.sh
} >"$OUT.tmp"

chmod +x "$OUT.tmp"

# ---- payload --------------------------------------------------------
{
	printf '\n\n# %s\n' "__I3_EVERFOREST_PAYLOAD_BELOW__"
	printf '# Assets below are base64-encoded archives. Do not edit by hand.\n'
	for a in icons.tar.xz gtk-theme.tar.xz wallpaper.jpg.xz user-avatar.jpg sddm-theme.tar.xz fonts.tar.xz bar.tar.xz bar-c.tar.xz st-patches.tar.xz; do
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
