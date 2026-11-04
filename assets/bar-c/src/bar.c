/* Window, event loop and layout. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <signal.h>
#include <time.h>
#include <sys/select.h>

#include <X11/Xatom.h>
#include <X11/Xutil.h>

#include "bar.h"

/* Set by SIGHUP: re-read bar.json so an opacity change applies without a
 * restart. A flag (not work in the handler) keeps the handler async-signal-safe. */
static volatile sig_atomic_t reload_requested;

static void
on_reload(int sig)
{
	(void)sig;
	reload_requested = 1;
}

static unsigned long
now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (unsigned long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void
set_dock_hints(Bar *b)
{
	Atom type = XInternAtom(b->dpy, "_NET_WM_WINDOW_TYPE", False);
	Atom dock = XInternAtom(b->dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
	Atom strut = XInternAtom(b->dpy, "_NET_WM_STRUT_PARTIAL", False);
	Atom strut0 = XInternAtom(b->dpy, "_NET_WM_STRUT", False);
	long vals[12] = { 0, 0, WINDOW_HEIGHT, 0, 0, 0, 0, 0, 0, b->width - 1, 0, 0 };
	long simple[4] = { 0, 0, WINDOW_HEIGHT, 0 };

	XChangeProperty(b->dpy, b->win, type, XA_ATOM, 32,
	                PropModeReplace, (unsigned char *)&dock, 1);
	XChangeProperty(b->dpy, b->win, strut, XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)vals, 12);
	XChangeProperty(b->dpy, b->win, strut0, XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)simple, 4);
}

/* ---- state refresh ----------------------------------------------------- */

static void
refresh_workspaces(Bar *b)
{
	char buf[8192];
	FILE *f;

	b->st.ws_count = 0;
	f = popen("i3-msg -t get_workspaces 2>/dev/null", "r");
	if (!f)
		return;
	size_t n = fread(buf, 1, sizeof buf - 1, f);
	buf[n] = '\0';
	pclose(f);

	const char *p = buf;
	while ((p = strstr(p, "\"num\":")) != NULL && b->st.ws_count < 16) {
		int num = atoi(p + 6);
		const char *seg_end = strstr(p, "},");
		char seg[1024];
		size_t len;

		if (!seg_end) seg_end = p + strlen(p);
		len = (size_t)(seg_end - p);
		if (len >= sizeof seg) len = sizeof seg - 1;
		memcpy(seg, p, len);
		seg[len] = '\0';

		if (num > 0) {
			int i = b->st.ws_count++;
			b->st.ws[i].num = num;
			b->st.ws[i].focused = strstr(seg, "\"focused\":true") != NULL;
			b->st.ws[i].urgent = strstr(seg, "\"urgent\":true") != NULL;
		}
		p = seg_end;
	}
}

static void
refresh_clock(Bar *b)
{
	time_t t = time(NULL);
	struct tm tm;

	localtime_r(&t, &tm);
	strftime(b->st.clock, sizeof b->st.clock, "%H:%M", &tm);
	strftime(b->st.date, sizeof b->st.date, "%A %d %B %Y", &tm);
}

static void
refresh_memory(Bar *b)
{
	/* /proc/meminfo directly: no fork on the event-loop thread. */
	FILE *f = fopen("/proc/meminfo", "r");
	unsigned long total = 0, avail = 0, val;
	char key[64], unit[16];

	b->st.memory[0] = '\0';
	if (!f)
		return;
	while (fscanf(f, "%63s %lu %15s", key, &val, unit) == 3) {
		if (strcmp(key, "MemTotal:") == 0) total = val;
		else if (strcmp(key, "MemAvailable:") == 0) { avail = val; break; }
	}
	fclose(f);
	if (total)
		snprintf(b->st.memory, sizeof b->st.memory, "\xef\x87\x80 %d%%",
		         (int)((total - avail) * 100 / total));
}

static void
refresh_cpu(Bar *b)
{
	static unsigned long long prev_total, prev_idle;
	FILE *f = fopen("/proc/stat", "r");
	unsigned long long v[8] = { 0 };
	unsigned long long total = 0, idle;
	char line[256];

	if (!f)
		return;
	if (!fgets(line, sizeof line, f)) { fclose(f); return; }
	fclose(f);

	sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
	       &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7]);
	for (int i = 0; i < 8; i++) total += v[i];
	idle = v[3] + v[4];

	if (prev_total) {
		unsigned long long dt = total - prev_total;
		unsigned long long di = idle - prev_idle;
		int pct = dt ? (int)((dt - di) * 100 / dt) : 0;

		if (pct < 0) pct = 0;
		if (pct > 100) pct = 100;
		b->st.cpu_value = pct;
		b->st.cpu_seq++;
		b->st.cpu_last_ms = now_ms();

		if (b->st.cpu_len == 0) {
			/* First sample: pre-fill so the line spans the full width. */
			for (int i = 0; i < GRAPH_POINTS; i++)
				b->st.cpu_history[i] = (char)pct;
			b->st.cpu_len = GRAPH_POINTS;
		} else if (b->st.cpu_len < GRAPH_POINTS) {
			b->st.cpu_history[b->st.cpu_len++] = (char)pct;
		} else {
			memmove(b->st.cpu_history, b->st.cpu_history + 1,
			        GRAPH_POINTS - 1);
			b->st.cpu_history[GRAPH_POINTS - 1] = (char)pct;
		}
	}
	prev_total = total;
	prev_idle = idle;
}

static void
refresh_network(Bar *b)
{
	/* Read the interface state from sysfs: nmcli would fork a process on every
	 * tick, which is long enough to be felt during a workspace switch. */
	FILE *f = fopen("/sys/class/net/wlp4s0/operstate", "r");
	char buf[32] = "";

	if (!f) {
		b->st.network_connected = 0;
		return;
	}
	if (fgets(buf, sizeof buf, f))
		b->st.network_connected = strncmp(buf, "up", 2) == 0;
	fclose(f);
}

void
bar_refresh(Bar *b)
{
	unsigned long t = now_ms();

	/* After a click, poll quickly until i3 has caught up (ws_fast_until). */
	{
		unsigned long interval = (t < b->ws_fast_until) ? 25 : 60;

		if (t - b->last_ws >= interval) {
			refresh_workspaces(b);
			b->last_ws = t;
			/* Repaint as soon as the focus actually moved. */
			/* The set of workspaces rarely changes, but the focused flag
			 * flips on every switch - that is what the pill follows. */
			unsigned long sig = 0;

			for (int i = 0; i < b->st.ws_count; i++) {
				sig = sig * 31 + (unsigned long)b->st.ws[i].num;
				sig = sig * 31 + (unsigned long)b->st.ws[i].focused;
				sig = sig * 31 + (unsigned long)b->st.ws[i].urgent;
			}
			sig = sig * 31 + (unsigned long)b->st.ws_count;

			if (sig != b->ws_sig) {
				b->ws_sig = sig;
				b->ws_dirty = 1;
			}
		}
	}
	if (t - b->last_clock >= TICK_CLOCK_MS) {
		refresh_clock(b);
		b->last_clock = t;
	}
	if (t - b->last_sysinfo >= TICK_SYSINFO_MS) {
		refresh_memory(b);
		refresh_cpu(b);
		b->last_sysinfo = t;
	}
	if (t - b->last_network >= TICK_NETWORK_MS) {
		refresh_network(b);
		b->last_network = t;
	}
}

/* ---- window ------------------------------------------------------------ */

/* Transparency preset. bar.json is the installer's source of truth, and
 * ST_BAR_OPACITY lets a one-off run override it without editing the file. */
static double
load_opacity(void)
{
	const char *env = getenv("ST_BAR_OPACITY");
	char buf[256] = "";
	char path[512];
	FILE *f = NULL;

	if (env && *env) {
		if (!strcmp(env, "soft")) return OPACITY_SOFT;
		if (!strcmp(env, "clear")) return OPACITY_CLEAR;
		return OPACITY_SOLID;
	}

	/* Resolve the config through $HOME: writing "/home/builder/..." worked
	 * only on this one machine and silently fell back to solid everywhere
	 * else. */
	{
		const char *home = getenv("HOME");

		if (home && *home) {
			snprintf(path, sizeof path, "%s/.config/i3-everforest/bar.json",
			         home);
			f = fopen(path, "r");
		}
	}
	if (f) {
		while (fgets(buf, sizeof buf, f)) {
			char *p = strstr(buf, "\"opacity\"");

			if (p && (p = strchr(p, ':')) && (p = strchr(p, '"'))) {
				char val[16];
				int i = 0;

				p++;
				while (*p && *p != '"' && i < 15)
					val[i++] = *p++;
				val[i] = '\0';
				if (!strcmp(val, "soft")) { fclose(f); return OPACITY_SOFT; }
				if (!strcmp(val, "clear")) { fclose(f); return OPACITY_CLEAR; }
				fclose(f);
				return OPACITY_SOLID;
			}
		}
		fclose(f);
	}
	return OPACITY_SOLID;
}

void
bar_init(Bar *b)
{
	int screen;
	XSetWindowAttributes attrs;
	XClassHint *cls;

	memset(b, 0, sizeof(*b));
	b->dpy = XOpenDisplay(NULL);
	if (!b->dpy) {
		fprintf(stderr, "bar: cannot open display\n");
		exit(1);
	}
	screen = DefaultScreen(b->dpy);
	b->screen = screen;
	b->width = DisplayWidth(b->dpy, screen);
	/* Prefer a 32-bit ARGB visual: without an alpha channel the compositor
	 * cannot blend the panel, so every opacity preset would look opaque. */
	{
		XVisualInfo vi;
		XVisualInfo *got;
		int n = 0;

		if (XMatchVisualInfo(b->dpy, screen, 32, TrueColor, &vi)) {
			b->visual = vi.visual;
			b->depth = 32;
			b->cmap = XCreateColormap(b->dpy,
			                          RootWindow(b->dpy, screen),
			                          b->visual, AllocNone);
		} else {
			/* Fall back only if the server has no ARGB visual at all. */
			got = XGetVisualInfo(b->dpy, VisualScreenMask, &vi, &n);
			if (got) XFree(got);
			b->visual = DefaultVisual(b->dpy, screen);
			b->cmap = DefaultColormap(b->dpy, screen);
			b->depth = DefaultDepth(b->dpy, screen);
		}
	}

	attrs.override_redirect = False;
	/* No background: cairo writes ARGB directly. */
	attrs.border_pixel = 0;
	attrs.colormap = b->cmap;
	attrs.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask |
	                   PointerMotionMask | StructureNotifyMask;

	b->win = XCreateWindow(b->dpy, RootWindow(b->dpy, screen),
	                       0, 0, b->width, WINDOW_HEIGHT, 0, b->depth,
	                       InputOutput, b->visual,
	                       CWBorderPixel | CWColormap | CWEventMask, &attrs);

	XStoreName(b->dpy, b->win, "i3-everforest-bar-c");

	cls = XAllocClassHint();
	if (cls) {
		cls->res_name = (char *)"i3-everforest-bar-c";
		cls->res_class = (char *)"i3-everforest-bar-c";
		XSetClassHint(b->dpy, b->win, cls);
		XFree(cls);
	}

	/* DOCK is the only type i3 reserves space for. Its dockarea container
	 * normally eats button events, so grab the buttons on our own window. */

	/* Set the strut while the window is still unmapped. i3 evaluates
	 * _NET_WM_STRUT_PARTIAL on MapNotify; an override-redirect window that
	 * advertises it afterwards is ignored, which is why the tiled windows were
	 * covering the bar. */
	set_dock_hints(b);
	XMapWindow(b->dpy, b->win);

	/* The managed dock loses its button mask on every i3 relayout, so a second
	 * override-redirect window sits on top purely to receive clicks. Map it
	 * after the dock so it stays above. */
	{
		XSetWindowAttributes ia;

		ia.override_redirect = True;
		ia.event_mask = ButtonPressMask | ButtonReleaseMask |
			               PointerMotionMask | LeaveWindowMask;

		/* InputOnly: no visual, so picom never composites it - an
		 * InputOutput overlay would be blurred and smear the bar. */
		b->input = XCreateWindow(b->dpy, RootWindow(b->dpy, screen),
		                         0, 0, b->width, WINDOW_HEIGHT, 0, 0,
		                         InputOnly, CopyFromParent,
		                         CWOverrideRedirect | CWEventMask, &ia);
		XStoreName(b->dpy, b->input, "i3-everforest-bar-input");
		XMapRaised(b->dpy, b->input);

		/* Claim the buttons for the strip area. i3's dock container is an
		 * override-redirect sibling that would otherwise receive them. */
		XGrabButton(b->dpy, AnyButton, AnyModifier, b->input, False,
		            ButtonPressMask | ButtonReleaseMask,
		            GrabModeAsync, GrabModeAsync, None, None);
	}

	XSelectInput(b->dpy, b->win,
	             ExposureMask | ButtonPressMask | ButtonReleaseMask |
	             PointerMotionMask | StructureNotifyMask);

	XSelectInput(b->dpy, b->win,
	             ExposureMask | ButtonPressMask | ButtonReleaseMask |
	             PointerMotionMask | StructureNotifyMask);

	b->hover_region = -1;
	b->tip_region = -1;
	b->tip_suppress = -1;
	b->pressed_region = -1;
	b->pressed_until = 0;
	b->panel_base = load_opacity();
	b->panel_alpha = b->panel_base;

	b->surface = cairo_xlib_surface_create(b->dpy, b->win, b->visual,
	                                       b->width, WINDOW_HEIGHT);
	b->cr = cairo_create(b->surface);

	bar_refresh(b);
	bar_sample_under(b);
}

/* ---- layout ------------------------------------------------------------ */

/* Sample the wallpaper behind the panel, column by column.
 *
 * A single sample was enough to tint the whole strip, but the wallpaper varies
 * across the screen, so the bar never matched the desktop at its edges. Sample
 * the row just below the panel at 64 evenly spaced positions instead. */
void
bar_sample_under(Bar *b)
{
	XImage *img;
	/* Read the wallpaper at the strip's own rows: the bar is an ARGB
	 * overlay, so the root pixmap there is the unobstructed desktop. */
	int y = MARGIN_TOP + BAR_HEIGHT / 2;
	int n = 64;

	if (y >= DisplayHeight(b->dpy, b->screen))
		y = DisplayHeight(b->dpy, b->screen) - 1;

	img = XGetImage(b->dpy, RootWindow(b->dpy, b->screen),
	                0, y, b->width, 1, AllPlanes, ZPixmap);
	if (!img) {
		for (int i = 0; i < n; i++) {
			b->under_r[i] = b->under_g[i] = b->under_b[i] = 0.09;
		}
		b->under_n = n;
		return;
	}

	b->under_n = n;
	for (int i = 0; i < n; i++) {
		int x = (b->width - 1) * i / (n - 1);
		unsigned long p = XGetPixel(img, x, 0);
		b->under_r[i] = (double)((p & img->red_mask) >> 16) / 255.0;
		b->under_g[i] = (double)((p & img->green_mask) >> 8) / 255.0;
		b->under_b[i] = (double)(p & img->blue_mask) / 255.0;
	}
	XDestroyImage(img);
}

/* Which region contains (x,y), or -1. */
static int
region_at(Bar *b, int x, int y)
{
	for (int i = 0; i < b->region_count; i++) {
		HitRegion *r = &b->regions[i];

		if (x >= r->x && x < r->x + r->w &&
		    y >= r->y && y < r->y + r->h)
			return i;
	}
	return -1;
}


/* Re-derive the hovered control from the real pointer position, and keep the
 * tooltip in step.
 *
 * Called every frame from the main loop, NOT from bar_draw: the 30Hz fast path
 * only repaints the graph and never reaches bar_draw, so a tooltip left under
 * the pointer survived while the pointer was over a popup.
 */
void
bar_update_hover(Bar *b)
{
	Window rw, cw;
	int rx, ry, wx, wy;
	unsigned int mask;
	int was = b->hover_region;

	/* Query through the ROOT window: XQueryPointer(b->win, ...) keeps
	 * reporting the last coordinates inside the bar once the pointer leaves,
	 * so "pointer left" was never detected. */
	if (!XQueryPointer(b->dpy, RootWindow(b->dpy, b->screen),
	                   &rw, &cw, &rx, &ry, &wx, &wy, &mask) ||
	    !(cw == b->input || cw == b->win) ||
	    rx < 0 || ry < 0 || rx >= b->width || ry >= WINDOW_HEIGHT) {
		b->hover_region = -1;
	} else {
		b->pointer_x = rx;
		b->pointer_y = ry;
		b->hover_region = region_at(b, rx, ry);
	}

	/* Clear the click-suppression as soon as the pointer leaves the control
	 * that was clicked. */
	if (b->tip_suppress >= 0 && b->hover_region != b->tip_suppress)
		b->tip_suppress = -1;

	/* Tooltip follows the hovered control, and disappears the moment the
	 * pointer leaves the bar or lands on any other window. A control that was
	 * just clicked keeps its tooltip hidden until the pointer leaves it. */
	{
		int want_tip = (b->hover_region == b->tip_suppress) ? -1
		                                                    : b->hover_region;

		if (want_tip != b->tip_region) {
			b->tip_region = want_tip;
			if (want_tip >= 0) {
				HitRegion *hr = &b->regions[want_tip];

				tooltip_show(b, hr->tip, hr->x, hr->w);
			} else {
				tooltip_close(b);
			}
		}
	}

	if (b->hover_region >= 0 && b->hover_region < b->region_count) {
		HitRegion *hr = &b->regions[b->hover_region];

		b->hb_x = hr->x;
		b->hb_y = hr->y;
		b->hb_w = hr->w;
		b->hb_h = hr->h;
	}

	/* Repaint the veil when the hovered control changed. */
	if (was != b->hover_region)
		bar_draw_region_only(b, b->hb_x, b->hb_y, b->hb_w, b->hb_h);
}

void
bar_draw(Bar *b)
{
	int y = MARGIN_TOP;
	int x, rx;
	int widths[8], n = 0;

	bar_sample_under(b);
	draw_panel(b);
	free_regions(b);

	/* left: workspaces | separator | screenshot | ime */
	x = MARGIN_SIDE + LEFT_INSET;
	x += module_workspaces(b, x, y, BAR_HEIGHT);
	x += module_separator(b, x, y, BAR_HEIGHT);
	x += module_screenshot(b, x, y, BAR_HEIGHT);
	x += module_ime(b, x, y, BAR_HEIGHT);

	/* right, measured first so they can be placed from the edge inwards */
	/* Visual order left->right is sysinfo, launcher, notifications, power,
	 * clock, network. Since placement walks in from the right edge, the list
	 * itself is reversed: network ends up rightmost. */
	widths[n++] = module_network(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_clock(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_power(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_notifications(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_launcher(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_sysinfo(b, MEASURE_X, y, BAR_HEIGHT);

	rx = b->width - MARGIN_SIDE - RIGHT_INSET;
	for (int i = 0; i < n; i++) {
		rx -= widths[i];
		switch (i) {
		case 0: module_network(b, rx, y, BAR_HEIGHT); break;
		case 1: module_clock(b, rx, y, BAR_HEIGHT); break;
		case 2: module_power(b, rx, y, BAR_HEIGHT); break;
		case 3: module_notifications(b, rx, y, BAR_HEIGHT); break;
		case 4: module_launcher(b, rx, y, BAR_HEIGHT); break;
		case 5: module_sysinfo(b, rx, y, BAR_HEIGHT); break;
		}
	}

	/* centre: window title, clipped to the space between the clusters */
	int mid = x + (rx - x) / 2;
	module_window(b, mid, y, BAR_HEIGHT, rx - x);

	/* Snapshot the bar WITH its modules but WITHOUT any veil: hover repaints
	 * restore from this instead of re-running eleven modules every frame. */
	{
		if (!b->baseline) {
			b->baseline = cairo_image_surface_create(
				CAIRO_FORMAT_ARGB32, b->width, WINDOW_HEIGHT);
		}
		if (b->baseline &&
		    cairo_surface_status(b->baseline) == CAIRO_STATUS_SUCCESS) {
			cairo_t *bc = cairo_create(b->baseline);

			cairo_set_operator(bc, CAIRO_OPERATOR_SOURCE);
			cairo_set_source_surface(bc, b->surface, 0, 0);
			cairo_paint(bc);
			cairo_destroy(bc);
			b->baseline_valid = 1;
		}
	}

	/* Expire a stale press (release may never arrive if a popup takes focus). */
	if (b->pressed_region >= 0 && now_ms() > b->pressed_until) {
		b->pressed_region = -1;
	}

	/* Press/hover veil, drawn over everything so it tints icon and text too. */
	if (b->pressed_region >= 0) {
		draw_feedback(b, b->fb_x, b->fb_y, b->fb_w, b->fb_h,
		              PILL_RADIUS, PRESS_ALPHA);
	} else if (b->hover_region >= 0) {
		draw_feedback(b, b->hb_x, b->hb_y, b->hb_w, b->hb_h,
		              PILL_RADIUS, HOVER_ALPHA);
	}

	cairo_surface_flush(b->surface);
	XFlush(b->dpy);
}

/* Repaint one pill plus its veil, clipped to that rectangle.
 *
 * Hovering used to trigger a full bar_draw (eleven modules + text shaping) at
 * 30Hz, which showed up as ~2% CPU. Repainting only the affected pill keeps the
 * feedback identical at a fraction of the cost. */
void
bar_draw_region_only(Bar *b, int rx, int ry, int rw, int rh)
{
	cairo_t *cr = b->cr;
	int x0 = rx - 3, y0 = ry - 3, w0 = rw + 6, h0 = rh + 6;

	if (!b->baseline_valid || !b->baseline)
		return;

	cairo_save(cr);
	cairo_rectangle(cr, x0, y0, w0, h0);
	cairo_clip(cr);

	/* Restore the untouched pixels for this rectangle. */
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_surface(cr, b->baseline, 0, 0);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Then tint it, exactly as the full draw would. */
	{
		int idx = region_at(b, rx + rw / 2, ry + rh / 2);

		if (idx >= 0) {
			HitRegion *r = &b->regions[idx];

			draw_feedback(b, r->x, r->y, r->w, r->h, PILL_RADIUS,
			              b->pressed_region >= 0 ? PRESS_ALPHA
			                                     : HOVER_ALPHA);
		}
	}

	cairo_restore(cr);
	cairo_surface_flush(b->surface);
	cairo_surface_mark_dirty_rectangle(b->surface, x0, y0, w0, h0);
	XFlush(b->dpy);
}

/* Repaint only the sysinfo graph band.
 *
 * The graph is the only thing that moves every frame; redrawing the whole bar
 * (eleven modules plus text shaping) cannot reach 30Hz. This clips to the
 * graph rectangle, re-paints the pill behind it and the line on top. */
void
bar_draw_graph_only(Bar *b)
{
	cairo_t *cr;
	cairo_surface_t *off;
	cairo_t *ocr;

	if (!b->graph_w)
		return;

	/* Draw the band into an offscreen surface and blit it once.
	 *
	 * Painting the pill background and then the line straight onto the window
	 * left a frame where only the background was visible - the 30Hz flicker.
	 * An offscreen buffer makes the update atomic. */
	off = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
	                                 b->graph_w, b->graph_h);
	if (cairo_surface_status(off) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(off);
		return;
	}
	ocr = cairo_create(off);
	cairo_set_source_rgb(ocr, C_PILL);
	cairo_paint(ocr);
	module_draw_cpu_graph_at(b, ocr, 0, 0, b->graph_w, b->graph_h);
	cairo_destroy(ocr);

	cr = b->cr;
	cairo_save(cr);
	cairo_rectangle(cr, b->graph_x, b->graph_y, b->graph_w, b->graph_h);
	cairo_clip(cr);
	cairo_set_source_surface(cr, off, b->graph_x, b->graph_y);
	cairo_paint(cr);
	cairo_restore(cr);

	cairo_surface_destroy(off);

	cairo_surface_flush(b->surface);
	cairo_surface_mark_dirty_rectangle(b->surface, b->graph_x, b->graph_y,
	                                   b->graph_w, b->graph_h);
	XFlush(b->dpy);
}

/* Pointer moved: repaint only when the hovered region changes. */
void
bar_handle_motion(Bar *b, int x, int y)
{
	int hit = region_at(b, x, y);

	b->pointer_x = x;
	b->pointer_y = y;
	if (hit == b->hover_region)
		return;
	b->hover_region = hit;
	bar_draw(b);
}

/* Button released: clear the pressed state and repaint. */
void
bar_handle_release(Bar *b, int x, int y)
{
	(void)x;
	(void)y;
	if (b->pressed_region < 0)
		return;
	b->pressed_region = -1;
	bar_draw(b);
}

void
bar_handle_click(Bar *b, int x, int y, int button)
{
	for (int i = 0; i < b->region_count; i++) {
		HitRegion *r = &b->regions[i];
		if (x >= r->x && x < r->x + r->w && y >= r->y && y < r->y + r->h) {
			const char *cmd = NULL;

			/* Flash the press now. The command may open a window that covers
			 * the bar, so this is the only moment the feedback can be seen. */
			b->pressed_region = i;
			b->pressed_until = now_ms() + 600;

			/* A click means the user has read the hint and acted on it, so the
			 * tooltip goes away immediately and stays away until the pointer
			 * leaves this control and comes back. */
			if (b->tip_region != -1) {
				b->tip_region = -1;
				tooltip_close(b);
			}
			/* Suppress this control's tooltip until the pointer leaves it, or
			 * the hover update would pop it straight back up. */
			b->tip_suppress = i;

			b->fb_x = r->x;
			b->fb_y = r->y;
			b->fb_w = r->w;
			b->fb_h = r->h;
			bar_draw(b);
			cairo_surface_flush(b->surface);
			XFlush(b->dpy);
			if (button == Button1) cmd = r->left;
			else if (button == Button2) cmd = r->middle;
			else if (button == Button3) cmd = r->right;
			if (cmd) {
				/* Workspace switches go straight to i3-msg without the
				 * double-fork of spawn(): that path waits on a child and
				 * costs the latency we are trying to remove. */
				if (strncmp(cmd, "i3-msg ", 7) == 0) {
					pid_t p = fork();

					if (p == 0) {
						setsid();
						execl("/bin/sh", "sh", "-c", cmd,
						      (char *)NULL);
						_exit(127);
					}
					b->ws_fast_until = now_ms() + 2000;
					return;
				}
				spawn(cmd);
				return;
			}
		}
	}
}

/* ---- main -------------------------------------------------------------- */

int
main(void)
{
	Bar b;
	int xfd;
	unsigned long last_tick = 0;

	bar_init(&b);
	bar_draw(&b);
	signal(SIGHUP, on_reload);
	xfd = ConnectionNumber(b.dpy);

	for (;;) {
		fd_set fds;
		struct timeval tv = { 0, TICK_MS * 1000 };
		int rc;

		FD_ZERO(&fds);
		FD_SET(xfd, &fds);

		/* While a workspace change is expected, wake up much sooner so the
		 * highlight can follow within a frame or two. */
		if (now_ms() < b.ws_fast_until) {
			tv.tv_sec = 0;
			tv.tv_usec = 8 * 1000;   /* 8ms */
		}

		rc = select(xfd + 1, &fds, NULL, NULL, &tv);
		if (rc > 0 && FD_ISSET(xfd, &fds)) {
			while (XPending(b.dpy)) {
				XEvent ev;
				XNextEvent(b.dpy, &ev);
				switch (ev.type) {
				case Expose:
					if (ev.xexpose.count == 0)
						bar_draw(&b);
					break;
				case ButtonPress:
					bar_handle_click(&b, ev.xbutton.x_root,
					                 ev.xbutton.y_root,
					                 ev.xbutton.button);
					break;
				case ButtonRelease:
					bar_handle_release(&b, ev.xbutton.x_root,
					                   ev.xbutton.y_root);
					break;
				case MotionNotify:
					bar_handle_motion(&b, ev.xmotion.x_root,
					                  ev.xmotion.y_root);
					break;
				case LeaveNotify:
					if (b.hover_region >= 0) {
						b.hover_region = -1;
						b.tip_region = -1;
						tooltip_close(&b);
						bar_draw(&b);
					}
					break;
				case ConfigureNotify:
					if (ev.xconfigure.width != b.width) {
						b.width = ev.xconfigure.width;
						cairo_xlib_surface_set_size(
							b.surface, b.width, WINDOW_HEIGHT);
						set_dock_hints(&b);
						bar_draw(&b);
					}
					break;
				}
			}
		}

		if (reload_requested) {
			reload_requested = 0;
			b.panel_base = load_opacity();
			b.panel_alpha = b.panel_base;
			bar_draw(&b);
		}

		/* Redraw at most twice a second, and only if the clock text or the
		 * graph actually moved. A full redraw forks several helpers and pushes
		 * a new image to X, which delays anything i3 is doing at that moment. */
		unsigned long t = now_ms();
		if (t - last_tick >= (now_ms() < b.ws_fast_until ? 8 : TICK_MS)) {
			unsigned long prev_seq = b.st.cpu_seq;
			int prev_cpu = b.st.cpu_value;
			char prev_clock[16];

			last_tick = t;
			memcpy(prev_clock, b.st.clock, sizeof prev_clock);

			/* Cheap state only: the graph needs a new sample, the clock a new
			 * minute. The costly parts (i3 tree, memory) run on their own
			 * timers inside bar_refresh. */
			bar_refresh(&b);
			(void)prev_clock;

			/* The graph scrolls continuously, so repaint whenever the bar is
			 * visible. Text modules are cheap to redraw compared with the
			 * smoothness this buys. */
			/* Scroll phase.
			 *
			 * Clamping at 1.0 made the line crawl, stall at the end of the
			 * interval, then jump when the next sample landed - the visible
			 * stutter. Wrap the phase instead: it keeps advancing at a
			 * constant rate forever, and the wrap coincides exactly with the
			 * sample being appended, so the shift and the array slide cancel
			 * out and motion stays even. */
			if (b.st.cpu_last_ms) {
				double ph = (double)(t - b.st.cpu_last_ms) /
				            TICK_SYSINFO_MS;

				b.st.cpu_frac = ph - (long)ph;
				if (ph < 0)
					b.st.cpu_frac = 0.0;
			} else {
				b.st.cpu_frac = 0.0;
			}


			(void)prev_seq; (void)prev_cpu;

			/* Always re-derive the hover, even when nothing is hovered:
			 * this is what dismisses a tooltip whose control the pointer has
			 * left (for example onto a rofi menu). */
			bar_update_hover(&b);

			if (b.ws_dirty) {
				/* The workspace set changed: the pills must be repainted. */
				b.ws_dirty = 0;
				bar_draw(&b);
			} else if (b.pressed_region >= 0) {
				/* Restore the pill from the baseline and re-tint it. */
				bar_draw_region_only(&b, b.fb_x, b.fb_y, b.fb_w, b.fb_h);
			} else {
				/* Fast path: only the graph moves. */
				bar_draw_graph_only(&b);
			}




		}
		/* i3 restacks its dock container above us on every relayout; keep the
		 * click layer on top. */
		{
			static unsigned long last_raise;
			if (b.input && t - last_raise >= 500) {
				last_raise = t;
				XRaiseWindow(b.dpy, b.input);
			}
		}
	}
	return 0;
}
