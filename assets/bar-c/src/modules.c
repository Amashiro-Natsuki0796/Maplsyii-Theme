/* Modules, each transcribed from the Python original.
 *
 * Every module returns the width it occupies (including its own margins) and,
 * when x is a real coordinate, draws itself and registers its click regions.
 * MEASURE_X means "report the width only" - see config.h. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#include "bar.h"

static void
capture(const char *cmd, char *out, size_t n)
{
	FILE *f = popen(cmd, "r");
	if (!f) { out[0] = '\0'; return; }
	if (!fgets(out, (int)n, f))
		out[0] = '\0';
	out[strcspn(out, "\n")] = '\0';
	pclose(f);
}

/* ---------- workspaces ------------------------------------------------- */

int
module_workspaces(Bar *b, int x, int y, int h)
{
	int start = x;
	(void)h;

	for (int i = 0; i < b->st.ws_count; i++) {
		int num = b->st.ws[i].num;
		int focused = b->st.ws[i].focused;
		int urgent = b->st.ws[i].urgent;

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

			char *cmd = malloc(64);
			if (cmd) {
				snprintf(cmd, 64, "i3-msg workspace number %d", num);
				add_region(b, bx, by, pw, bh, cmd, NULL, NULL);
			}
		}

		/* Each button advances by its width plus both side margins. */
		start += pw + 2 * WS_MARGIN_X;
	}

	/* box.workspaces { margin-right: 4px } */
	return (start - x) + 4;
}

/* ---------- separator -------------------------------------------------- */

int
module_separator(Bar *b, int x, int y, int h)
{
	const char *glyph = "|";
	int tw = text_width_sized(b, glyph, FONT_SIZE_SEP, PANGO_WEIGHT_NORMAL);
	int w = tw + 2 * PAD_SEP;

	if (x != MEASURE_X)
		draw_text_n(b, x + PAD_SEP, y, glyph, FONT_SIZE_SEP,
		            PANGO_WEIGHT_NORMAL, C_SEP);
	(void)h;
	return w + 2 * 2;   /* margin: 5px 2px */
}

/* ---------- window title ----------------------------------------------- */

int
module_window(Bar *b, int x, int y, int h, int max_w)
{
	char buf[512];
	capture("xdotool getactivewindow getwindowname 2>/dev/null", buf, sizeof buf);
	(void)h;
	if (!buf[0])
		return 0;

	if (x == MEASURE_X)
		return text_width(b, buf);

	char shown[512];
	snprintf(shown, sizeof shown, "%s", buf);

	/* waybar's max-length 60, then fit to the available width by dropping one
	 * character at a time (the previous version shaved four). */
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

/* ---------- clock (bare, no pill) -------------------------------------- */

int
module_clock(Bar *b, int x, int y, int h)
{
	const char *label = b->st.clock;
	int tw = text_width(b, label);
	int w = tw + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		draw_text_n(b, x + PILL_PAD_X, y, label, FONT_SIZE, FONT_WEIGHT,
		            C_CREAM);
		add_region(b, x + PILL_MARGIN, y + PILL_MARGIN, w,
		           h - 2 * PILL_MARGIN,
		           "i3-everforest-calendar", NULL,
		           "i3-everforest-calendar terminal");
		set_region_tip(b, "Clock\n"
		                 "Left: calendar   Right: calendar in a terminal");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- sysinfo: memory % + CPU line graph ------------------------ */

void
module_draw_cpu_graph_at(Bar *b, cairo_t *cr, int x, int y, int w, int h)
{
	int n = b->st.cpu_len;
	double step;
	double pts[GRAPH_POINTS][2];

	if (n < 2)
		return;

	step = (double)w / (GRAPH_POINTS - 1);

	/* Continuous motion without a snap at the sample boundary.
	 *
	 * Each new sample enters from the right edge and slides into place over the
	 * following interval, while the rest of the line creeps left at the same
	 * rate. The previous version reset the offset to zero on every sample,
	 * which pulled the whole line back a step - the visible "jump". */
	/* Fractional progress toward the next sample, 0..1. */
	double frac = b->st.cpu_frac;

	if (frac < 0) frac = 0;
	if (frac >= 1.0) frac -= 1.0;

	/* The newest sample stays pinned to the right edge; every older point
	 * drifts left continuously.
	 *
	 * The previous version shifted the whole line left by frac*step, which
	 * pushed the head past the right edge where the clip cut it off. It then
	 * reappeared a pixel at a time - the visible hopping. Pinning the head and
	 * moving the body keeps both edges still. */
	for (int i = 0; i < n; i++) {
		int v = (unsigned char)b->st.cpu_history[i];
		double px;

		if (i == n - 1) {
			px = w;                       /* head: always on the edge */
		} else {
			/* Body: each sample is one step apart, shifted left by the
			 * elapsed fraction of the current interval. */
			px = w - (double)(n - 1 - i) * step - frac * step;
		}

		double py = h - (v / 100.0) * (h - 2) - 1;
		pts[i][0] = px;
		pts[i][1] = py;
	}

	cairo_save(cr);
	cairo_translate(cr, x, y);

	/* Filled area under the line, then the line itself. */
	cairo_new_path(cr);
	cairo_move_to(cr, pts[0][0], h);
	for (int i = 0; i < n; i++)
		cairo_line_to(cr, pts[i][0], pts[i][1]);
	cairo_line_to(cr, pts[n - 1][0], h);
	cairo_close_path(cr);
	cairo_set_source_rgba(cr, 0.902, 0.706, 0.314, 0.26);
	cairo_fill(cr);

	/* Faint 50% guide, so the trend has a reference point. */
	cairo_set_source_rgba(cr, 1, 1, 1, 0.10);
	cairo_set_line_width(cr, 1.0);
	cairo_move_to(cr, 0, h / 2.0);
	cairo_line_to(cr, w, h / 2.0);
	cairo_stroke(cr);

	cairo_new_path(cr);
	for (int i = 0; i < n; i++) {
		if (i == 0)
			cairo_move_to(cr, pts[i][0], pts[i][1]);
		else
			cairo_line_to(cr, pts[i][0], pts[i][1]);
	}
	cairo_set_source_rgb(cr, 0.902, 0.706, 0.314);
	cairo_set_line_width(cr, 1.6);
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
	cairo_stroke(cr);

	cairo_restore(cr);
}

int
module_sysinfo(Bar *b, int x, int y, int h)
{
	const char *label = b->st.memory;   /* includes the memory glyph */
	int tw = text_width(b, label);
	int w = tw + SYSINFO_LABEL_PAD + 2 * PAD_SYSINFO + 6 + GRAPH_WIDTH;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		/* Hairline outline: the pill is only a shade lighter than the bar, so
		 * without it the control's edges are hard to see. */
		{
			cairo_set_source_rgb(b->cr, SYSINFO_EDGE);
			cairo_set_line_width(b->cr, SYSINFO_EDGE_W);
			{
				double r = PILL_RADIUS;
				double x0 = bx + 0.5, y0 = by + 0.5;
				double x1 = bx + w - 0.5, y1 = by + bh - 0.5;

				cairo_new_sub_path(b->cr);
				cairo_arc(b->cr, x1 - r, y0 + r, r, -M_PI/2, 0);
				cairo_arc(b->cr, x1 - r, y1 - r, r, 0, M_PI/2);
				cairo_arc(b->cr, x0 + r, y1 - r, r, M_PI/2, M_PI);
				cairo_arc(b->cr, x0 + r, y0 + r, r, M_PI, 3*M_PI/2);
				cairo_close_path(b->cr);
				cairo_stroke(b->cr);
			}
		}
		draw_text(b, bx + PAD_SYSINFO, y, label, C_WHITE);

		/* Remember where the graph is so the 30Hz path can clip to it. */
		b->graph_x = bx + PAD_SYSINFO + tw + SYSINFO_LABEL_PAD + 6;
		b->graph_y = by + (bh - GRAPH_HEIGHT) / 2;
		b->graph_w = GRAPH_WIDTH;
		b->graph_h = GRAPH_HEIGHT;

		module_draw_cpu_graph(b, b->graph_x, b->graph_y,
		                      GRAPH_WIDTH, GRAPH_HEIGHT);

		add_region(b, bx, by, w, bh,
		           "i3-everforest-sysinfo-monitor", NULL,
		           "i3-everforest-sysinfo-monitor");
		set_region_tip(b, "Memory usage\n"
		                 "Line = CPU history, click for a live view");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- network ---------------------------------------------------- */

int
module_network(Bar *b, int x, int y, int h)
{
	/* The icon is stroked as three arcs instead of a font glyph, so the dot,
	 * the middle arc and the outer arc can each carry its own colour.
	 *
	 * The old glyph measured 17px wide, so the pill was 39px (17 + 2*11).
	 * Reserving exactly that keeps the surrounding layout identical; the arcs
	 * are drawn in an 18x14 box centred inside the pill. */
	int w = 17 + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);

		/* Icon box matches the old glyph: 18 wide, 14 tall. */
		{
			int ix = bx + (w - 18) / 2;
			int iy = by + (bh - 14) / 2;

			if (b->st.network_connected) {
				draw_wifi(b, ix, iy, 18, 14,
				          WIFI_TOP, WIFI_MID, WIFI_DOT);
			} else {
				/* Disconnected keeps the same shape in the alert colour, so
				 * the state reads at a glance. */
				draw_wifi(b, ix, iy, 18, 14,
				          C_ALERT, C_ALERT, C_ALERT);
			}
		}

		add_region(b, bx, by, w, bh,
		           "i3-everforest-wifi", NULL,
		           "i3-everforest-wifi config");
		set_region_tip(b, "Network\n"
		                 "Left: scan networks   Right: connection details");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- launcher --------------------------------------------------- */

int
module_launcher(Bar *b, int x, int y, int h)
{
	const char *glyph = "\uf31a";
	int tw = text_width(b, glyph);
	int cw = tw < ICON_MIN_W ? ICON_MIN_W : tw;
	int w = cw + 2 * PAD_LAUNCHER;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_LAUNCHER);
		draw_text_n(b, bx + PAD_LAUNCHER + (cw - tw) / 2, y + 1, glyph,
		            FONT_SIZE, PANGO_WEIGHT_HEAVY, C_LAUNCHER_FG);
		add_region(b, bx, by, w, bh,
		           "rofi -show drun -theme i3-everforest",
		           NULL, NULL);
		set_region_tip(b, "Application launcher\nMod+D");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- notifications ---------------------------------------------- */

int
module_notifications(Bar *b, int x, int y, int h)
{
	const char *glyph = "\uf0f3";
	int tw = text_width(b, glyph);
	int cw = tw < ICON_MIN_W ? ICON_MIN_W : tw;
	int w = cw + 2 * PAD_NOTIF;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill_r(b, bx, by, w, bh, R_NOTIF, C_NOTIF);
		draw_text_n(b, bx + PAD_NOTIF + (cw - tw) / 2, y + 1, glyph,
		            FONT_SIZE, PANGO_WEIGHT_HEAVY, C_WHITE);
		add_region(b, bx, by, w, bh,
		           "i3-everforest-notifications history",
		           "i3-everforest-notifications clear",
		           "i3-everforest-notifications toggle");
		set_region_tip(b, "Notifications\n"
		                 "Left: history   Middle: clear   Right: do-not-disturb");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- power ------------------------------------------------------ */

int
module_power(Bar *b, int x, int y, int h)
{
	const char *glyph = "\uf011";
	int tw = text_width(b, glyph);
	int w = tw + 2 * PAD_POWER;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill_r(b, bx, by, w, bh, R_POWER, C_POWER);
		draw_text_n(b, bx + PAD_POWER, y, glyph, FONT_SIZE,
		            FONT_WEIGHT, C_CREAM);
		add_region(b, bx, by, w, bh, "i3-everforest-powermenu", NULL, NULL);
		set_region_tip(b, "Power menu");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- screenshot ------------------------------------------------- */

int
module_screenshot(Bar *b, int x, int y, int h)
{
	const char *glyph = "\uf030";
	int tw = text_width(b, glyph);
	int w = tw + 2 * PILL_PAD_X;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		draw_text(b, bx + PILL_PAD_X, y, glyph, C_WHITE);
		add_region(b, bx, by, w, bh,
		           "i3-everforest-shot",
		           "i3-everforest-pick",
		           "i3-everforest-shot region");
		set_region_tip(b, "Screenshot / colour picker\n"
		                 "Left: full screen   Middle: pick a colour\n"
		                 "Right: drag a region");
	}
	return w + 2 * PILL_MARGIN;
}

/* ---------- IME -------------------------------------------------------- */

int
module_ime(Bar *b, int x, int y, int h)
{
	const char *glyph = "\uf11c";
	int tw = text_width(b, glyph);
	int cw = tw < ICON_MIN_W ? ICON_MIN_W : tw;
	int w = cw + 2 * PAD_IME;

	if (x != MEASURE_X) {
		int bx = x + PILL_MARGIN;
		int by = y + PILL_MARGIN;
		int bh = h - 2 * PILL_MARGIN;

		draw_pill(b, bx, by, w, bh, C_PILL);
		draw_text(b, bx + PAD_IME + (cw - tw) / 2, y, glyph, C_WHITE);
		add_region(b, bx, by, w, bh,
		           "i3-everforest-ime toggle", NULL,
		           "i3-everforest-ime config");
		set_region_tip(b, "Input method\n"
		                 "Left: switch   Right: settings");
	}
	return w + 2 * PILL_MARGIN;
}

void
module_draw_cpu_graph(Bar *b, int x, int y, int w, int h)
{
	module_draw_cpu_graph_at(b, b->cr, x, y, w, h);
}
