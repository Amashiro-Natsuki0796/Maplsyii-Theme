/* The bar's modules, ported one-for-one from the X11 bar (assets/bar-c/src).
 *
 * Every module returns the width it occupies and, when the x coordinate is
 * real, draws itself and registers its click regions. The X11 original had a
 * MEASURE_X sentinel for the measure-only pass; here the two passes are explicit
 * (measure functions are separate), which keeps the drawing code free of the
 * "is this a real draw?" branch.
 */
#include <math.h>
#include <stdio.h>
#include <stdio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bar.h"

/* ---------- workspaces ------------------------------------------------- */
int
module_workspaces(Bar *b, int x, int y, int h)
{
	int start = x;
	(void)h;

	for (int i = 0; i < b->ws_count; i++) {
		int num = b->ws[i].num;
		int focused = b->ws[i].focused;
		int urgent = b->ws[i].urgent;

		char label[16];
		snprintf(label, sizeof label, "%d", num);

		int tw = text_width(b, label);
		int cw = tw < WS_MIN_W ? WS_MIN_W : tw;
		int pw = cw + 2 * WS_PAD_X;

		int bx = start + WS_MARGIN_X;
		int by = y + PILL_MARGIN + 1;
		int bh = WS_MIN_H;

		if (x != MEASURE_X) {
			if (focused) {
				draw_pill_r(b, bx, by, pw, bh, WS_RADIUS, C_AMBER);
				draw_text_n(b, bx + (pw - tw) / 2, y, label,
				            FONT_SIZE, FONT_WEIGHT_WS_ACTIVE, C_DARK_FG);
			} else if (urgent) {
				draw_pill_r(b, bx, by, pw, bh, WS_RADIUS, C_ALERT);
				draw_text_n(b, bx + (pw - tw) / 2, y, label,
				            FONT_SIZE, FONT_WEIGHT, C_DARK_FG);
			} else {
				draw_text_n(b, bx + (pw - tw) / 2, y, label,
				            FONT_SIZE, FONT_WEIGHT, C_WHITE);
			}

			char cmd[64];
			snprintf(cmd, sizeof cmd, "swaymsg workspace number %d", num);
			add_region(b, bx, by, pw, bh, cmd, NULL, NULL);
		}

		start += pw + 2 * WS_MARGIN_X;
	}

	return (start - x) + 4;   /* box.workspaces { margin-right: 4px } */
}

/* ---------- separator -------------------------------------------------- */
int
module_separator(Bar *b, int x, int y, int h)
{
	const char *glyph = "|";
	int tw = text_width_sized(b, glyph, FONT_SIZE_SEP, PANGO_WEIGHT_NORMAL);
	int w = tw + 2 * PAD_SEP;

	(void)h;

	if (x != MEASURE_X)
		draw_text_n(b, x + PAD_SEP, y, glyph, FONT_SIZE_SEP,
		            PANGO_WEIGHT_NORMAL, C_SEP);

	return w + 2 * 2;   /* margin: 5px 2px */
}

/* Camera: left = full screenshot, middle = colour picker, right = region.
 * Same three-way split as the X11 bar, so the control behaves identically. */
int
module_screenshot(Bar *b, int x, int y, int h)
{
	const char *glyph = "\xef\x80\xb0";   /* U+F030 camera */
	int tw = text_width(b, glyph);
	int w = tw + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		draw_text(b, bx + PILL_PAD_X, y, glyph, C_WHITE);
		add_region(b, bx, by, w, bh,
		           "sway-everforest-shot",
		           "sway-everforest-pick",
		           "sway-everforest-shot region");
		set_region_tip(b, "Screenshot / colour picker\n"
		                 "Left: full screen   Middle: pick a colour\n"
		                 "Right: drag a region");
	}
	return w + 2 * PILL_MARGIN;
}

/* Keyboard glyph: left toggles the IME, right opens the configuration. */
int
module_ime(Bar *b, int x, int y, int h)
{
	const char *glyph = "\xef\x84\x9c";   /* U+F11C keyboard */
	int tw = text_width(b, glyph);
	int cw = tw < ICON_MIN_W ? ICON_MIN_W : tw;
	int w = cw + 2 * PAD_IME;

	(void)h;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = BAR_HEIGHT - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		draw_text(b, bx + PAD_IME + (cw - tw) / 2, y, glyph, C_WHITE);
		add_region(b, bx, by, w, bh,
		           "sway-everforest-ime toggle", NULL,
		           "sway-everforest-ime config");
		set_region_tip(b, "Input method\n"
		                 "Left: switch   Right: configure");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- CPU graph -------------------------------------------------- */
/* Straight port of module_draw_cpu_graph_at(): one rigid strip sliding left by
 * frac*step, clipped to the plot, with the last segment extrapolated so the
 * right border never gaps. The reasoning is unchanged from the X11 version. */
void
module_draw_cpu_graph(Bar *b, int x, int y, int w, int h)
{
	int n = b->cpu_count;
	double step = (double)w / (GRAPH_POINTS - 1);
	double pts[GRAPH_POINTS + 1][2];
	int np;

	if (n < 2)
		return;

	double frac = b->cpu_frac;
	if (frac < 0) frac = 0;
	if (frac > 1.0) frac = 1.0;

	for (int i = 0; i < n; i++) {
		int v = b->cpu_history[i];

		pts[i][0] = w - (double)(n - 1 - i) * step - frac * step;
		pts[i][1] = h - (v / 100.0) * (h - 2) - 1;
	}
	np = n;

	if (pts[np - 1][0] < w) {
		pts[np][0] = w + step;
		pts[np][1] = pts[np - 1][1];
		np++;
	}

	cairo_t *cr = b->cr;
	cairo_save(cr);
	cairo_translate(cr, x, y);
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_clip(cr);

	/* Filled area under the line. */
	cairo_new_path(cr);
	cairo_move_to(cr, pts[0][0], h);
	for (int i = 0; i < np; i++)
		cairo_line_to(cr, pts[i][0], pts[i][1]);
	cairo_line_to(cr, pts[np - 1][0], h);
	cairo_close_path(cr);
	cairo_set_source_rgba(cr, 0.902, 0.706, 0.314, 0.26);
	cairo_fill(cr);

	/* Faint 50% guide. */
	cairo_set_source_rgba(cr, 1, 1, 1, 0.10);
	cairo_set_line_width(cr, 1.0);
	cairo_move_to(cr, 0, h / 2.0);
	cairo_line_to(cr, w, h / 2.0);
	cairo_stroke(cr);

	/* The line itself. */
	cairo_new_path(cr);
	for (int i = 0; i < np; i++) {
		if (i == 0)
			cairo_move_to(cr, pts[i][0], pts[i][1]);
		else
			cairo_line_to(cr, pts[i][0], pts[i][1]);
	}
	cairo_set_source_rgb(cr, 0.902, 0.706, 0.314);
	cairo_set_line_width(cr, 1.6);
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);

	cairo_stroke(cr);

	cairo_restore(cr);
}

/* Hairline outline around the sysinfo pill: gtk's box-shadow inset. */
void
sysinfo_outline(Bar *b, int x, int y, int w, int h)
{
	cairo_t *cr = b->cr;

	rounded_rect(cr, x + 0.5, y + 0.5, w - 1, h - 1, PILL_RADIUS);
	cairo_set_source_rgba(cr, 0.55, 0.60, 0.58, 0.55);
	cairo_set_line_width(cr, 1.0);
	cairo_stroke(cr);
}

/* ---------- sysinfo (memory % + CPU line) ------------------------------ */
int
module_sysinfo(Bar *b, int x, int y, int h)
{
	char label[64];
	snprintf(label, sizeof label, "\xef\x87\x80 %d%%", b->memory_pct);
	/* \xef\x87\x80 = U+F1C0 database glyph */

	int tw = text_width(b, label);
	int w = tw + SYSINFO_LABEL_PAD + 2 * PAD_SYSINFO + 6 + GRAPH_WIDTH;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		sysinfo_outline(b, bx, by, w, bh);
		draw_text_in(b, bx + PAD_SYSINFO, by, bh, label,
		             FONT_SIZE, FONT_WEIGHT, C_WHITE);

		b->graph_x = bx;
		b->graph_y = by;
		b->graph_w = w;
		b->graph_h = bh;
		b->plot_x = bx + PAD_SYSINFO + tw + SYSINFO_LABEL_PAD + 6;
		b->plot_y = by + (bh - GRAPH_HEIGHT) / 2;
		b->plot_w = GRAPH_WIDTH;
		b->plot_h = GRAPH_HEIGHT;

		module_draw_cpu_graph(b, b->plot_x, b->plot_y,
		                      GRAPH_WIDTH, GRAPH_HEIGHT);

		add_region(b, bx, by, w, bh,
		           "sway-everforest-sysinfo-monitor", NULL,
		           "sway-everforest-sysinfo-monitor");
		set_region_tip(b, "Memory usage\n"
		                 "Line = CPU history, click for a live view");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- right-hand icon pills -------------------------------------- */
/* A coloured icon pill. `pad` is the per-module horizontal padding, matching
 * what the X11 bar reads from its config (PAD_LAUNCHER / PAD_NOTIF / ...):
 * each pill has its own inset, so one shared constant made every one of them
 * the wrong width. `minw` is the CSS min-width, applied only to the pills that
 * declare it. */
static int
icon_pill(Bar *b, int x, int y, int h, const char *glyph, int pad, int minw,
          double radius, int weight, int yoff,
          double bg_r, double bg_g, double bg_b,
          double fg_r, double fg_g, double fg_b,
          const char *tip, const char *left, const char *middle,
          const char *right)
{
	int tw = text_width(b, glyph);
	int cw = tw < minw ? minw : tw;
	int w = cw + 2 * pad;

	(void)h;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = BAR_HEIGHT - 2 * PILL_MARGIN;

		draw_pill_r(b, bx, by, w, bh, radius, bg_r, bg_g, bg_b);
		draw_text_n(b, bx + pad + (cw - tw) / 2, y + yoff, glyph,
		            FONT_SIZE, weight, fg_r, fg_g, fg_b);
		add_region(b, bx, by, w, bh, left, middle, right);
		if (tip)
			set_region_tip(b, tip);
	}
	return w + 2 * PILL_MARGIN;
}

int
module_launcher(Bar *b, int x, int y, int h)
{
	return icon_pill(b, x, y, h, "\xef\x8c\x9a",   /* U+F31A */
	                 PAD_LAUNCHER, ICON_MIN_W, R_LAUNCHER,
	                 PANGO_WEIGHT_HEAVY, 1,
	                 C_LAUNCHER, C_LAUNCHER_FG,
	                 "Application launcher\nMod+D\n"
	                 "Right: window switcher",
	                 /* --no-actions drops the secondary action list that
	                  * wofi otherwise builds from a .desktop file's Actions=
	                  * key. Browsers ship several (new window, private window,
	                  * profile manager), so a right click opened a nested menu
	                  * over the launcher; the launcher is meant to read as a flat
	                  * list of applications. */
	                 "wofi --show drun --no-actions", NULL,
	                 "wofi --show windows");
}

int
module_notifications(Bar *b, int x, int y, int h)
{
	return icon_pill(b, x, y, h, "\xef\x83\xb3",   /* U+F0F3 bell */
	                 PAD_NOTIF, ICON_MIN_W, R_NOTIF, FONT_WEIGHT, 1,
	                 C_NOTIF, C_WHITE,
	                 "Notifications\n"
	                 "Left: history   Middle: clear   Right: do not disturb",
	                 "sway-everforest-notifications history",
	                 "sway-everforest-notifications clear",
	                 "sway-everforest-notifications toggle");
}

int
module_power(Bar *b, int x, int y, int h)
{
	return icon_pill(b, x, y, h, "\xef\x80\x91",   /* U+F011 power */
	                 PAD_POWER, 0, R_POWER, FONT_WEIGHT, 0,
	                 C_POWER, C_CREAM,
	                 "Power menu",
	                 "sway-everforest-powermenu", NULL, NULL);
}

/* ---------- clock ------------------------------------------------------ */
int
module_clock(Bar *b, int x, int y, int h)
{
	const char *label = b->clock;
	int tw = text_width(b, label);
	int w = tw + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		draw_text_in(b, bx + PILL_PAD_X, by, bh, label,
		             FONT_SIZE, FONT_WEIGHT, C_TEXT);
		add_region(b, bx, by, w, bh,
		           "sway-everforest-calendar", NULL,
		           "sway-everforest-calendar terminal");
		set_region_tip(b, "Date and calendar\nClick to open");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- network ---------------------------------------------------- */
int
module_network(Bar *b, int x, int y, int h)
{
	/* Fixed pill width: the X11 bar reserves 17 + 2*11 for the icon it draws,
	 * which keeps the surrounding layout identical. */
	int w = 17 + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);

		/* Icon box matches the old glyph: 18 wide, 14 tall, centred. */
		{
			int ix = bx + (w - 18) / 2;
			int iy = by + (bh - 14) / 2;

			/* Wireless and wired get their own symbol; a machine with only
			 * an Ethernet port should not advertise a wifi icon it can never
			 * use. Connection state is carried by colour. */
			if (b->network_is_wifi) {
				if (b->network_connected)
					draw_wifi(b, ix, iy, 18, 14, WIFI_TOP, WIFI_MID, WIFI_DOT);
				else
					draw_wifi(b, ix, iy, 18, 14, C_ALERT, C_ALERT, C_ALERT);
			} else {
				if (b->network_connected)
					draw_ethernet(b, ix, iy, 18, 14, WIFI_DOT);
				else
					draw_ethernet(b, ix, iy, 18, 14, C_ALERT);
			}
		}

		add_region(b, bx, by, w, bh,
		           "sway-everforest-wifi", NULL,
		           "sway-everforest-wifi config");
		set_region_tip(b, "Network\n"
		                 "Left: scan networks   Right: connection details");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- centre: window title --------------------------------------- */
int
module_window(Bar *b, int x, int y, int h, int max_w)
{
	(void)h;
	if (!b->title[0])
		return 0;

	if (x == MEASURE_X)
		return text_width(b, b->title);

	char shown[512];
	snprintf(shown, sizeof shown, "%s", b->title);

	/* waybar's max-length 60, then fit to the available width by dropping one
	 * character at a time. */
	if (strlen(shown) > 60) {
		shown[57] = '\0';
		strcat(shown, "...");
	}
	while (text_width(b, shown) > max_w && strlen(shown) > 4) {
		size_t len = strlen(shown);
		if (len >= 4 && strcmp(shown + len - 3, "...") == 0)
			shown[len - 4] = '\0';
		else
			shown[len - 1] = '\0';
		if (strcmp(shown + strlen(shown) - 3, "...") != 0)
			strcat(shown, "...");
	}

	int tw = text_width(b, shown);
	draw_text(b, x - tw / 2, y, shown, C_TEXT);
	return tw;
}
