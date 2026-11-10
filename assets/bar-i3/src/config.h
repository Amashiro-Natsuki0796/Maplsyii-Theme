/* Everforest bar - geometry, palette and per-module styling.
 *
 * Every value here is transcribed from the Python bar that this replaces
 * (assets/bar/i3-everforest-bar.py), whose CSS block came from the original
 * waybar style. Keeping them in one place is what makes a 1:1 reproduction
 * checkable: each constant below names the CSS rule it came from. */
#ifndef EF_CONFIG_H
#define EF_CONFIG_H

/* cairo wants 0.0-1.0; the palette is written as hex triples. */
/* Expands to three float arguments: draw_pill(b, x, y, w, h, RGB(...)).
 * The comma expression is intentional; the pragma keeps -Wunused-value quiet
 * where the expansion appears in a non-variadic position. */
#define RGB(r, g, b) ((r) / 255.0), ((g) / 255.0), ((b) / 255.0)
#define RGBA(r, g, b, a) ((r) / 255.0), ((g) / 255.0), ((b) / 255.0), (a)

/* --- geometry (waybar: height 34, margin 6/6/8/8) ---------------------- */
#define BAR_HEIGHT      34
#define MARGIN_TOP      6
#define MARGIN_BOTTOM   6
#define MARGIN_SIDE     8
#define WINDOW_HEIGHT   (MARGIN_TOP + BAR_HEIGHT + MARGIN_BOTTOM)
#define PANEL_RADIUS    12.0
#define PILL_RADIUS     9.0
#define PILL_PAD_X      11      /* pill { padding: 0 11px } */
#define PILL_MARGIN     4       /* pill { margin: 4px 4px } */
#define PILL_MIN_HEIGHT 26      /* pill { min-height: 26px } */
#define WS_PAD_X        5       /* button.wsbtn { padding: 0 5px } */
#define WS_MARGIN_X     2       /* button.wsbtn { margin: 5px 2px } */
#define WS_MARGIN_Y     5
#define WS_MIN_W        29      /* button.wsbtn { min-width: 29px } */
#define WS_MIN_H        23
#define WS_RADIUS       11.0
#define LEFT_INSET      3       /* box.modules-left { margin-left: 3px } */
#define RIGHT_INSET     2       /* box.modules-right { margin-right: 2px } */
#define GRAPH_POINTS    40
#define GRAPH_WIDTH     46
#define GRAPH_HEIGHT    20

/* Per-module padding, straight from each CSS rule. */
#define PAD_IME         9       /* box.mod-ime { padding: 0 9px } */
#define PAD_LAUNCHER    13      /* box.mod-launcher { padding: 0 13px } */
#define PAD_NOTIF       10      /* box.mod-notifications { padding: 0 10px } */
#define PAD_POWER       12      /* box.mod-power { padding: 0 12px } */
#define PAD_SYSINFO     12      /* box.mod-sysinfo { padding: 0 12px } */
#define PAD_SEP         2       /* box.mod-separator { padding: 0 2px } */
#define SYSINFO_LABEL_PAD 5     /* Gtk.Label's implicit horizontal padding */
#define ICON_MIN_W      22      /* min-width: 22px for ime/launcher/notifications */

/* Radii that specific modules override. */
#define R_LAUNCHER      13.0    /* box.mod-launcher { border-radius: 13px } */
#define R_NOTIF         15.0    /* box.mod-notifications { border-radius: 15px } */
#define R_POWER         10.0    /* box.mod-power { border-radius: 10px } */

/* --- palette (the CSS colour variables) -------------------------------- */
#define C_BAR       RGB(0x17, 0x1b, 0x1c)
#define C_PILL      RGB(0x2f, 0x33, 0x36)
#define C_TEXT      RGB(0xd3, 0xc6, 0xaa)
#define C_CREAM     RGB(0xff, 0xfb, 0xef)
#define C_LIME      RGB(0xb9, 0xff, 0x66)
#define C_AMBER     RGB(0xff, 0xb0, 0x00)
#define C_LAUNCHER  RGB(0x00, 0xff, 0x00)
#define C_LAUNCHER_FG RGB(0x10, 0x24, 0x10)
#define C_NOTIF     RGB(0x7c, 0x7a, 0xff)
#define C_POWER     RGB(0xfa, 0x34, 0x33)
#define C_SEP       RGB(0x4a, 0x52, 0x50)
#define C_ALERT     RGB(0xe6, 0x7e, 0x80)
#define C_WHITE     RGB(0xff, 0xff, 0xff)
#define C_DARK_FG   RGB(0x17, 0x1b, 0x1c)

/* --- panel transparency -------------------------------------------------
 * Three presets, the same ones the installer writes into bar.json:
 *   solid  1.00   opaque (waybar's default look)
 *   soft   0.82   wallpaper barely shows through
 *   clear  0.55   clearly translucent
 * The value is read from bar.json at startup; ST_BAR_OPACITY overrides it. */
#define OPACITY_SOLID  1.00
#define OPACITY_SOFT   0.82
#define OPACITY_CLEAR  0.35

/* --- fonts ------------------------------------------------------------- */
#define FONT_FAMILY   "JetBrains Mono"
/* Pango accepts a comma-separated fallback list; the Nerd Font supplies the
 * icon glyphs exactly as the Python bar's CSS font stack did. */
#define FONT_STACK    "JetBrains Mono, Symbols Nerd Font, Font Awesome 6 Free, sans-serif"
#define FONT_SIZE     14.0
#define FONT_SIZE_SEP 16.0
#define FONT_WEIGHT   PANGO_WEIGHT_BOLD
#define FONT_WEIGHT_WS_ACTIVE PANGO_WEIGHT_HEAVY

/* sysinfo pill outline: a hairline in a lighter grey, otherwise the dark pill
 * blends into the dark bar behind it. */
#define SYSINFO_EDGE      RGB(0x5a, 0x62, 0x60)
#define SYSINFO_EDGE_W    1.0

/* WiFi glyph: drawn as three arcs so each can carry its own colour -
 * the dot is white, the middle arc pink, the outer arc blue. */
#define WIFI_DOT      RGB(0xFE, 0xFE, 0xFE)   /* #FEFEFE - the flag's white */
#define WIFI_MID      RGB(0xF4, 0xA7, 0xB9)   /* #F4A7B9 - pink, middle arc */
#define WIFI_TOP      RGB(0x7D, 0xD6, 0xFB)   /* #7DD6FB - light blue, outer arc */
/* Stroke width from the original glyph: its arcs are ~2.5px thick at 18px
 * wide, not the hairline 1.6px an earlier pass used. */
#define WIFI_STROKE   2.5

/* Press feedback: the pill is overdrawn with white at these alphas while the
 * pointer hovers it or a button is held. */
#define HOVER_ALPHA  0.18
#define PRESS_ALPHA  0.38

/* Sentinel x meaning "measure only, do not draw or register". */
#define MEASURE_X (-99999)

/* --- refresh cadence --------------------------------------------------- */
/* The main loop wakes for the CPU graph, the only continuously moving
 * element, and otherwise sleeps until X or i3 has an event. 15Hz is smooth
 * for a sparkline and halves the wakeups (and therefore the compositor's
 * work) against the old 30Hz. */
#define GRAPH_TICK_MS    66     /* 15Hz: CPU graph redraw cadence */
#define TICK_MS          33     /* retained for the click feedback path */
#define TICK_CLOCK_MS   1000
#define TICK_SYSINFO_MS 250
#define TICK_NETWORK_MS 3000

#endif
