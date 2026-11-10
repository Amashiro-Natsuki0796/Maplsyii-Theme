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
#include <X11/Xatom.h>

#include "bar.h"

/* Trim a byte string so it ends on a UTF-8 character boundary.
 *
 * fgets() stops mid-character when a window title is longer than the buffer,
 * and the resulting partial sequence made Pango warn "Invalid UTF-8 string" on
 * every repaint - thousands of lines a second. Backing up to the start of the
 * truncated character keeps the text valid.
 */
static void
trim_utf8(char *s)
{
	size_t len = strlen(s);

	if (len == 0)
		return;
	for (size_t i = len; i > 0 && i > len - 4; i--) {
		unsigned char c = (unsigned char)s[i - 1];

		if ((c & 0xC0) != 0x80) {
			size_t need = (c < 0x80) ? 1 : (c < 0xE0) ? 2 : (c < 0xF0) ? 3 : 4;

			if (i - 1 + need > len)
				s[i - 1] = '\0';
			return;
		}
	}
	s[len - (len > 3 ? 3 : len)] = '\0';
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

/* Read the active window's title straight from X, with no fork.
 *
 * This replaces `xdotool getactivewindow getwindowname`, which forked a
 * process on every redraw. Two problems with that:
 *
 *   - the fork is the bar's last remaining per-frame process spawn (~15/s);
 *   - while xdotool ran, the capture could return an empty string, and because
 *     hovering a control triggers a full redraw, moving the pointer onto the
 *     bar made the centre title disappear for a frame. That is the flicker.
 *
 * The result is cached against the active window id, so the X round trip only
 * happens when the user actually switches windows.
 */
static void
refresh_wintitle(Bar *b)
{
	Atom active = XInternAtom(b->dpy, "_NET_ACTIVE_WINDOW", False);
	Atom utf8 = XInternAtom(b->dpy, "UTF8_STRING", False);
	Atom netname = XInternAtom(b->dpy, "_NET_WM_NAME", False);
	Atom prop = None;
	int fmt = 0;
	unsigned long n = 0, after = 0;
	unsigned char *data = NULL;
	Window w = None;

	/* Which window is active? Ask the root window; fall back to input focus. */
	if (XGetWindowProperty(b->dpy, DefaultRootWindow(b->dpy), active, 0, 1,
	                       False, XA_WINDOW, &prop, &fmt, &n, &after,
	                       &data) == Success && data) {
		w = *(Window *)data;
		XFree(data);
		data = NULL;
	}
	if (w == None) {
		int revert;

		XGetInputFocus(b->dpy, &w, &revert);
		if (w == PointerRoot || w == None)
			return;
	}

	if (w == b->st.winid && b->st.wintitle[0])
		return;                      /* unchanged: keep the cached title */

	/* _NET_WM_NAME is UTF-8; WM_NAME may be Latin-1. Try the modern one
	 * first and only fall back when it is absent. */
	if (XGetWindowProperty(b->dpy, w, netname, 0, sizeof b->st.wintitle - 1,
	                       False, utf8, &prop, &fmt, &n, &after,
	                       &data) == Success && data) {
		snprintf(b->st.wintitle, sizeof b->st.wintitle, "%s", (char *)data);
		XFree(data);
	} else if (XFetchName(b->dpy, w, (char **)&data) && data) {
		snprintf(b->st.wintitle, sizeof b->st.wintitle, "%s", (char *)data);
		XFree(data);
	} else {
		b->st.wintitle[0] = '\0';
	}
	b->st.winid = w;
	trim_utf8(b->st.wintitle);
}

int
module_window(Bar *b, int x, int y, int h, int max_w)
{
	(void)h;
	refresh_wintitle(b);
	if (!b->st.wintitle[0])
		return 0;

	if (x == MEASURE_X)
		return text_width(b, b->st.wintitle);

	char shown[512];
	snprintf(shown, sizeof shown, "%s", b->st.wintitle);

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
		            C_TEXT);
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
	double step = (double)w / (GRAPH_POINTS - 1);
	double pts[GRAPH_POINTS + 1][2];
	int np;

	if (n < 2)
		return;

	/* Fractional progress toward the next sample, 0..1. */
	double frac = b->st.cpu_frac;

	if (frac < 0) frac = 0;
	if (frac > 1.0) frac = 1.0;

	/* One rigid strip, sliding left by frac*step.
	 *
	 * Every point uses the same formula, the newest included. That is what
	 * makes the motion continuous across a sample boundary: when the strip has
	 * travelled a whole step (frac reaches 1) the array shift and the phase
	 * reset cancel exactly, so the point that was at w - frac*step is now at
	 * w - step - 0, the same place.
	 *
	 * Pinning the newest sample to the right edge - which an earlier version
	 * did, because it looked calmer there - breaks that identity: the head is
	 * drawn at w no matter where the phase is, so the moment a new sample
	 * arrives the old head has to teleport left by (1-frac)*step, up to a
	 * full 1.18px, in a single frame. That was the stutter: a periodic lurch
	 * once per 250ms, which is exactly what "the line moves in bursts" means.
	 *
	 * Both ends are cut by the clip below, so neither terminus depends on a
	 * particular point sitting on the border. */
	for (int i = 0; i < n; i++) {
		int v = (unsigned char)b->st.cpu_history[i];

		pts[i][0] = w - (double)(n - 1 - i) * step - frac * step;
		pts[i][1] = h - (v / 100.0) * (h - 2) - 1;
	}
	np = n;

	/* Extend the strip past the right edge.
	 *
	 * The newest sample sits at w - frac*step, so as the phase grows the line
	 * stops short of the right border and a gap opens up. Continue the last
	 * segment (or, on a flat tail, a horizontal run) out to w + step so the
	 * clip has something to cut at the border. Without this the head would be
	 * a detached stub that visibly detaches and re-attaches every interval -
	 * trading one artefact for another. */
	if (pts[np - 1][0] < w) {
		double y0 = pts[np - 1][1];

		/* Flatten the very last bit, so a steep final segment does not shoot
		 * off the top of the plot when extrapolated. */
		pts[np][0] = w + step;
		pts[np][1] = y0;
		np++;
	}

	cairo_save(cr);
	cairo_translate(cr, x, y);

	/* Clip to the plot area.
	 *
	 * Without this the sliding tail was painted over the pill padding and the
	 * memory label to its left, and the fill under the line reached into that
	 * gap as well. Clipping gives the left edge the same hard border the right
	 * edge has always had, so the line reads as a window onto a scrolling
	 * trace instead of a strip whose end wanders. */
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_clip(cr);

	/* Filled area under the line, then the line itself. */
	cairo_new_path(cr);
	cairo_move_to(cr, pts[0][0], h);
	for (int i = 0; i < np; i++)
		cairo_line_to(cr, pts[i][0], pts[i][1]);
	cairo_line_to(cr, pts[np - 1][0], h);
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
	for (int i = 0; i < np; i++) {
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

/* Hairline outline around the sysinfo pill.
 *
 * The pill is only a shade lighter than the bar, so without this the control's
 * edges are hard to see. Shared by the full draw and the 30Hz realtime band:
 * when the band repainted the pill without it, hovering made the outline
 * flicker away and come back.
 */
void
sysinfo_outline(Bar *b, int bx, int by, int w, int bh)
{
	cairo_t *cr = b->cr;
	double r = PILL_RADIUS;
	double x0 = bx + 0.5, y0 = by + 0.5;
	double x1 = bx + w - 0.5, y1 = by + bh - 0.5;

	cairo_save(cr);
	cairo_set_source_rgb(cr, SYSINFO_EDGE);
	cairo_set_line_width(cr, SYSINFO_EDGE_W);
	cairo_new_sub_path(cr);
	cairo_arc(cr, x1 - r, y0 + r, r, -M_PI / 2, 0);
	cairo_arc(cr, x1 - r, y1 - r, r, 0, M_PI / 2);
	cairo_arc(cr, x0 + r, y1 - r, r, M_PI / 2, M_PI);
	cairo_arc(cr, x0 + r, y0 + r, r, M_PI, 3 * M_PI / 2);
	cairo_close_path(cr);
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
		sysinfo_outline(b, bx, by, w, bh);
		/* Centre in the pill, not in the bar: the pill is 2*PILL_MARGIN
		 * shorter, so bar-centred text sat visibly high. */
		draw_text_in(b, bx + PAD_SYSINFO, by, bh, label,
		             FONT_SIZE, FONT_WEIGHT, C_WHITE);

		/* Remember where the graph is so the 30Hz path can clip to it. */
		/* The fast path repaints this rectangle every frame, so it must cover
		 * the memory text as well as the graph. It used to be the graph alone,
		 * which left the percentage frozen at whatever value the last full
		 * redraw happened to draw - it only moved when the pointer entered the
		 * bar and forced one. */
		b->graph_x = bx;
		b->graph_y = by;
		b->graph_w = w;
		b->graph_h = bh;
		/* Where the graph itself starts, for the actual plot. */
		b->plot_x = bx + PAD_SYSINFO + tw + SYSINFO_LABEL_PAD + 6;
		b->plot_y = by + (bh - GRAPH_HEIGHT) / 2;
		b->plot_w = GRAPH_WIDTH;
		b->plot_h = GRAPH_HEIGHT;

		module_draw_cpu_graph(b, b->plot_x, b->plot_y,
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

			/* Wireless and wired get their own symbol; a machine with only
			 * an Ethernet port should not advertise a wifi icon it can never
			 * use. Connected state is carried by colour: the tricolour wifi
			 * arcs or a plain terminal-coloured plug when up, alert red when
			 * down. */
			if (b->st.network_is_wifi) {
				if (b->st.network_connected)
					draw_wifi(b, ix, iy, 18, 14,
					          WIFI_TOP, WIFI_MID, WIFI_DOT);
				else
					draw_wifi(b, ix, iy, 18, 14,
					          C_ALERT, C_ALERT, C_ALERT);
			} else {
				if (b->st.network_connected)
					draw_ethernet(b, ix, iy, 18, 14,
					              WIFI_DOT);
				else
					draw_ethernet(b, ix, iy, 18, 14,
					              C_ALERT);
			}
		}

		add_region(b, bx, by, w, bh,
		           "i3-everforest-wifi", NULL,
		           "i3-everforest-wifi config");
		set_region_tip(b, b->st.network_is_wifi
		                 ? "Wi-Fi\nLeft: scan networks   Right: connection details"
		                 : "Ethernet\nLeft: network settings   Right: connection details");
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

		draw_pill_r(b, bx, by, w, bh, R_LAUNCHER, C_LAUNCHER);
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
