/* Main: state, event loop, input handling.
 *
 * Structure is the same as the X11 bar so behaviour matches:
 *   - a 15Hz tick drives the CPU graph and the cheap state refreshes
 *   - workspace changes arrive as sway IPC events and repaint the pills
 *   - pointer enter/motion/leave drives the hover veil, button events run the
 *     region's command
 *
 * What differs is the transport: instead of an Xlib event queue and an ARGB
 * X window, this reads events from the Wayland fd (and sway's IPC fd) with a
 * single poll(), paints into a wl_shm buffer, and commits the surface.
 */
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/wait.h>
#include <unistd.h>

#include "bar.h"

static int running = 1;

static void
on_signal(int sig)
{
	(void)sig;
	running = 0;
}

/* Bind cairo to the current shm buffer.
 *
 * Called after the first configure (which allocates the buffer) and again if
 * the compositor ever changes the surface size, since cairo_image_surface
 * holds the raw pointer and stride it was created with.
 */
static void
bar_cairo_setup(Bar *b)
{
	int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, b->wl.width);

	if (b->cr) {
		cairo_destroy(b->cr);
		b->cr = NULL;
	}
	if (b->surface) {
		cairo_surface_destroy(b->surface);
		b->surface = NULL;
	}
	if (b->baseline) {
		cairo_surface_destroy(b->baseline);
		b->baseline = NULL;
		b->baseline_valid = 0;
	}

	b->surface = cairo_image_surface_create_for_data(
	    b->wl.shm_data, CAIRO_FORMAT_ARGB32,
	    b->wl.width, b->wl.height, stride);
	b->cr = cairo_create(b->surface);
}

/* Bar transparency. $BAR_WL_OPACITY accepts soft/clear/solid, matching the
 * presets the i3 rice writes into bar.json. */
static double
load_opacity(void)
{
	const char *env = getenv("BAR_WL_OPACITY");

	if (env && *env) {
		if (strcmp(env, "soft") == 0)
			return OPACITY_SOFT;
		if (strcmp(env, "clear") == 0)
			return OPACITY_CLEAR;
	}
	return OPACITY_SOLID;
}

/* =====================  state refresh  ================================= */

/* Find `key` within [obj, end) and return the integer that follows.
 * Returns 0 when the key is absent, which is the right default for all three
 * workspace fields. */
static int
field_int(const char *obj, const char *end, const char *key, size_t keylen)
{
	const char *q = obj;

	while ((q = strstr(q, key)) != NULL) {
		if (q >= end)
			return 0;
		q += keylen;
		while (*q == ' ' || *q == '\t')
			q++;
		return atoi(q);
	}
	return 0;
}

/* Parse the boolean that follows `key`.
 *
 * sway serialises with spaces after the colon ("focused": true), while i3's
 * compact output has none. Skipping the whitespace here is what makes the
 * focused flag work at all - matching on "true" right after the key missed
 * every value and left every pill unhighlighted. */
static int
field_bool(const char *obj, const char *end, const char *key, size_t keylen)
{
	const char *q;

	if (!obj || !key)
		return 0;

	q = strstr(obj, key);
	if (!q || q >= end)
		return 0;

	q += keylen;
	while (*q == ' ' || *q == '\t')
		q++;
	return strncmp(q, "true", 4) == 0;
}

static void
refresh_workspaces(Bar *b)
{
	char buf[8192];

	b->ws_count = 0;
	if (sway_get_workspaces(buf, sizeof buf) < 0)
		return;

	/* Walk the array one object at a time, counting braces so nested objects
	 * (each workspace has a "rect") do not truncate the entry. */
	const char *p = buf;
	while (*p && b->ws_count < 16) {
		const char *obj = strchr(p, '{');
		const char *end;
		int depth = 0, in_str = 0;

		if (!obj)
			break;

		end = obj;
		while (*end) {
			if (in_str) {
				if (*end == '\\' && end[1])
					end++;
				else if (*end == '"')
					in_str = 0;
			} else if (*end == '"') {
				in_str = 1;
			} else if (*end == '{') {
				depth++;
			} else if (*end == '}') {
				if (--depth == 0)
					break;
			}
			end++;
		}
		if (!*end)
			break;

		WsInfo *wsi = &b->ws[b->ws_count];

		wsi->num = 0;
		wsi->focused = 0;
		wsi->urgent = 0;

		/* Search only inside this object.
		 *
		 * strstr() walks past `end` happily, so a workspace with no "urgent"
		 * key picked up the next one's value - which is how the focused flag
		 * ended up on the wrong pill. The helper below stops at `end`. */
		wsi->num = field_int(obj, end, "\"num\":", 6);
		wsi->focused = field_bool(obj, end, "\"focused\":", 10);
		wsi->urgent = field_bool(obj, end, "\"urgent\":", 9);

		b->ws_count++;
		p = end + 1;
	}

}

static void
refresh_clock(Bar *b)
{
	time_t t = time(NULL);
	struct tm tm;

	localtime_r(&t, &tm);
	strftime(b->clock, sizeof b->clock, "%H:%M", &tm);
	strftime(b->date, sizeof b->date, "%A %d %B %Y", &tm);
}

static void
refresh_memory(Bar *b)
{
	FILE *f = fopen("/proc/meminfo", "r");
	unsigned long total = 0, avail = 0;
	char line[256];

	if (!f)
		return;
	while (fgets(line, sizeof line, f)) {
		if (sscanf(line, "MemTotal: %lu", &total) == 1)
			continue;
		if (sscanf(line, "MemAvailable: %lu", &avail) == 1)
			continue;
	}
	fclose(f);

	if (total > 0)
		b->memory_pct = (int)((total - avail) * 100 / total);
}

static void
refresh_cpu(Bar *b)
{
	FILE *f = fopen("/proc/stat", "r");
	char line[512];
	unsigned long long v[8] = { 0 };
	unsigned long long total = 0, idle;
	int n;

	if (!f)
		return;
	if (!fgets(line, sizeof line, f)) {
		fclose(f);
		return;
	}
	fclose(f);

	n = sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
	           &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7]);
	if (n < 4)
		return;

	for (int i = 0; i < 8; i++)
		total += v[i];
	idle = v[3] + v[4];   /* idle + iowait */

	if (b->cpu_seen && total > b->prev_total) {
		unsigned long long dt = total - b->prev_total;
		unsigned long long di = idle >= b->prev_idle ? idle - b->prev_idle : 0;
		int pct = (int)((dt - di) * 100 / dt);

		if (pct < 0) pct = 0;
		if (pct > 100) pct = 100;
		b->cpu_value = pct;

		/* Shift the history left and append. */
		if (b->cpu_count < GRAPH_POINTS) {
			b->cpu_history[b->cpu_count++] = pct;
		} else {
			memmove(b->cpu_history, b->cpu_history + 1,
			        (GRAPH_POINTS - 1) * sizeof b->cpu_history[0]);
			b->cpu_history[GRAPH_POINTS - 1] = pct;
		}
		b->cpu_last_ms = now_ms();
	}
	b->prev_total = total;
	b->prev_idle = idle;
	b->cpu_seen = 1;
}

static void
refresh_network(Bar *b)
{
	/* Discover the link instead of shelling out.
	 *
	 * The previous version ran `nmcli -t -f STATE general` every three
	 * seconds: a fork per tick for one word of text. /sys/class/net carries the
	 * same information with no process at all.
	 *
	 * Wireless is detected by the per-device `wireless` directory, not by the
	 * numeric type field - some drivers report wlan interfaces as ARPHRD_ETHER,
	 * which made a type-based check pick the wrong icon.
	 */
	DIR *d = opendir("/sys/class/net");
	struct dirent *e;
	int wifi_up = 0, wired_up = 0, saw_wifi = 0, saw_wired = 0;

	b->network_connected = 0;
	b->network_is_wifi = 1;

	if (!d)
		return;

	while ((e = readdir(d)) != NULL) {
		char path[288], buf[32] = "";
		int is_wifi, up;
		FILE *f;

		if (e->d_name[0] == '.' || strcmp(e->d_name, "lo") == 0)
			continue;

		snprintf(path, sizeof path, "/sys/class/net/%.200s/wireless", e->d_name);
		is_wifi = access(path, F_OK) == 0;

		snprintf(path, sizeof path, "/sys/class/net/%.200s/carrier", e->d_name);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (fgets(buf, sizeof buf, f))
			buf[strcspn(buf, "\n")] = '\0';
		fclose(f);
		up = buf[0] == '1';

		if (is_wifi) { saw_wifi = 1; if (up) wifi_up = 1; }
		else         { saw_wired = 1; if (up) wired_up = 1; }
	}
	closedir(d);

	if (wifi_up || (saw_wifi && !saw_wired)) {
		b->network_is_wifi = 1;
		b->network_connected = wifi_up;
	} else if (wired_up || saw_wired) {
		b->network_is_wifi = 0;
		b->network_connected = wired_up;
	} else {
		b->network_is_wifi = 1;
		b->network_connected = 0;
	}
}

/* Re-read the focused window's title.
 *
 * Returns 1 when the text changed, so the caller can repaint. Without that
 * signal a title update was invisible: the only repaint triggers were a
 * workspace change and the CPU graph's partial redraw, and switching between
 * two windows in the same workspace changes neither.
 */
static int
refresh_title(Bar *b)
{
	char title[512];

	if (sway_get_active_app(title, sizeof title, NULL, 0) != 0)
		return 0;
	if (strcmp(b->title, title) == 0)
		return 0;

	snprintf(b->title, sizeof b->title, "%s", title);
	return 1;
}

static void
bar_refresh(Bar *b)
{
	unsigned long t = now_ms();

	/* Workspaces are event driven: the main loop sets ws_dirty when sway sends
	 * a workspace/window event, and this re-reads the list only then. */
	if (b->ws_dirty) {
		refresh_workspaces(b);

		unsigned long sig = 0;
		for (int i = 0; i < b->ws_count; i++) {
			sig = sig * 31 + (unsigned long)b->ws[i].num;
			sig = sig * 31 + (unsigned long)b->ws[i].focused;
			sig = sig * 31 + (unsigned long)b->ws[i].urgent;
		}
		sig = sig * 31 + (unsigned long)b->ws_count;
		b->ws_sig = sig;
	}
	if (t - b->last_clock >= TICK_CLOCK_MS) {
		refresh_clock(b);
		b->last_clock = t;
	}
	if (t - b->last_sysinfo >= TICK_SYSINFO_MS) {
		refresh_memory(b);
		refresh_cpu(b);
		b->last_sysinfo = t;

		/* The title is cheap to re-read but must not be fetched on every
		 * tick: it costs an IPC round trip to sway. Polling it alongside the
		 * sysinfo sample is enough for a click-to-focus change to appear
		 * within one frame or two, and the event loop also forces a refresh
		 * on window events (see ws_dirty below). */
		if (refresh_title(b))
			b->title_dirty = 1;
	}
	if (t - b->last_network >= TICK_NETWORK_MS) {
		refresh_network(b);
		b->last_network = t;
	}

	/* Scroll phase for the CPU graph, same maths as the X11 bar: divide by the
	 * measured interval and clamp at 1. */
	if (b->cpu_last_ms) {
		double iv = TICK_SYSINFO_MS;
		double ph = (b->cpu_last_ms >= t)
		                ? 0.0
		                : (double)(t - b->cpu_last_ms) / iv;

		if (ph > 1) ph = 1;
		b->cpu_frac = ph;
	} else {
		b->cpu_frac = 0.0;
	}
}

/* =====================  drawing  ======================================= */

static void
free_regions(Bar *b)
{
	for (int i = 0; i < b->region_count; i++) {
		free(b->regions[i].left);
		free(b->regions[i].middle);
		free(b->regions[i].right);
		free(b->regions[i].tip);
	}
	b->region_count = 0;
}

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

static void
bar_draw(Bar *b)
{
	int y = MARGIN_TOP;
	int x, rx;
	int widths[8], n = 0;

	draw_panel(b);
	free_regions(b);

	/* left: workspaces | separator | screenshot | ime */
	x = MARGIN_SIDE + LEFT_INSET;
	x += module_workspaces(b, x, y, BAR_HEIGHT);
	x += module_separator(b, x, y, BAR_HEIGHT);
	x += module_screenshot(b, x, y, BAR_HEIGHT);
	x += module_ime(b, x, y, BAR_HEIGHT);

	/* right: measure first, then place from the edge inwards. The visual order
	 * is sysinfo, launcher, notifications, power, clock, network, so the
	 * measurement list is reversed. */
	widths[n++] = module_network(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_clock(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_power(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_notifications(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_launcher(b, MEASURE_X, y, BAR_HEIGHT);
	widths[n++] = module_sysinfo(b, MEASURE_X, y, BAR_HEIGHT);

	rx = b->wl.width - MARGIN_SIDE - 8;
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

	/* centre: window title, clipped to the gap between the clusters */
	{
		int mid = x + (rx - x) / 2;
		module_window(b, mid, y, BAR_HEIGHT, rx - x);
	}

	/* Snapshot without any veil: hover repaints restore from this. */
	{
		if (!b->baseline) {
			b->baseline = cairo_image_surface_create(
			    CAIRO_FORMAT_ARGB32, b->wl.width, WINDOW_HEIGHT);
		}
		if (b->baseline &&
		    cairo_surface_status(b->baseline) == CAIRO_STATUS_SUCCESS) {
			cairo_t *bc = cairo_create(b->baseline);

			/* cairo_create never returns NULL: on failure it returns an
			 * object in an error state, and every subsequent call on it is a
			 * no-op. Painting through it would silently leave the baseline
			 * blank, so check before relying on it. */
			if (bc && cairo_status(bc) == CAIRO_STATUS_SUCCESS) {
				cairo_set_operator(bc, CAIRO_OPERATOR_SOURCE);
				cairo_set_source_surface(bc, b->surface, 0, 0);
				cairo_paint(bc);
				b->baseline_valid = 1;
			}
			if (bc)
				cairo_destroy(bc);
		}
	}

	/* Expire a stale press (release may never arrive). */
	if (b->pressed_region >= 0 && now_ms() > b->pressed_until)
		b->pressed_region = -1;

	/* Veil over everything, so it tints icon and text too. */
	if (b->pressed_region >= 0)
		draw_feedback(b, b->fb_x, b->fb_y, b->fb_w, b->fb_h,
		              PILL_RADIUS, PRESS_ALPHA);
	else if (b->hover_region >= 0)
		draw_feedback(b, b->hb_x, b->hb_y, b->hb_w, b->hb_h,
		              PILL_RADIUS, HOVER_ALPHA);

	cairo_surface_flush(b->surface);
	wl_commit(&b->wl);
}

/* Repaint only the sysinfo band.
 *
 * The CPU line is the only thing that moves between samples, and it lives in
 * one small pill, so redrawing the whole 1600x46 surface at 30Hz spends most of
 * its time on modules that did not change. This clips to the band, repaints the
 * pill, its outline and the memory text (they share the rectangle), and redraws
 * the graph on top - the same split the X11 bar makes with
 * bar_draw_graph_only().
 */
void
bar_draw_graph_only(Bar *b)
{
	cairo_t *cr = b->cr;
	int px, py, pw, ph;

	if (!b->plot_w || !b->plot_h)
		return;

	/* Repaint the plot rectangle only - not the whole sysinfo pill.
	 *
	 * Everything else in the pill (background, hairline outline, the memory
	 * figure) is static between samples, and the plot sits at least 4px inside
	 * the pill on every side, so it never overlaps the rounded corner or the
	 * outline. Re-drawing them 60 times a second was pure waste: a pango text
	 * layout is two orders of magnitude more expensive than the 46x20
	 * polyline.
	 *
	 * The extra pixel of bleed covers the antialiased edge of the previous
	 * frame's line, which would otherwise leave a faint trail as it scrolls. */
	px = b->plot_x - 1;
	py = b->plot_y - 1;
	pw = b->plot_w + 2;
	ph = b->plot_h + 2;

	cairo_save(cr);
	cairo_rectangle(cr, px, py, pw, ph);
	cairo_clip(cr);

	/* Flat pill colour: restore the background the line was drawn over. */
	cairo_set_source_rgb(cr, C_PILL);
	cairo_paint(cr);

	module_draw_cpu_graph(b, b->plot_x, b->plot_y, b->plot_w, b->plot_h);

	cairo_restore(cr);
	cairo_surface_flush(b->surface);

	wl_commit_rect(&b->wl, px, py, pw, ph);
}

/* =====================  input  ========================================= */

/* Does this command put a menu on screen that the bar should own?
 *
 * Matching on "wofi"/"rofi" is not enough: most controls run a helper script
 * (sway-everforest-wifi, ...-ime, ...-calendar) which starts the menu itself,
 * so the string never appears in the click command. Those scripts all end in a
 * launcher, and a second click on the icon has to close what the first one
 * opened - so they are listed by name.
 *
 * Commands that merely show a notification (screenshot, notifications history)
 * are deliberately excluded: there is nothing to toggle.
 */
static int
opens_menu(const char *cmd)
{
	static const char *const menus[] = {
		"wofi", "rofi",
		"sway-everforest-wifi",
		"sway-everforest-ime",
		"sway-everforest-calendar",
		"sway-everforest-powermenu",
		"sway-everforest-notifications history",
		NULL
	};

	if (!cmd || !*cmd)
		return 0;

	for (int i = 0; menus[i]; i++)
		if (strstr(cmd, menus[i]))
			return 1;
	return 0;
}

/* Is the tracked popup still alive?
 *
 * Reaps the child first: the bar is its parent, so a menu that the user closed
 * (Esc, picked an entry, clicked away) stays a zombie until someone waits on
 * it. waitpid(WNOHANG) both decides liveness and clears the zombie.
 */
static int
popup_alive(Bar *b)
{
	if (b->popup_pid <= 0)
		return 0;

	if (waitpid(b->popup_pid, NULL, WNOHANG) == 0)
		return 1;              /* still running */

	/* Exited (reaped above), or gone entirely. */
	b->popup_pid = 0;
	b->popup_region = -1;
	return 0;
}

/* Close the tracked popup, if one is open. */
static void
popup_close(Bar *b)
{
	if (b->popup_pid <= 0) {
		b->popup_region = -1;
		return;
	}
	/* Negative PID: kill the whole process group, so wofi goes away even if it
	 * forked helper processes. */
	kill(-b->popup_pid, SIGTERM);
	kill(b->popup_pid, SIGTERM);

	/* Reap it. wofi exits promptly on SIGTERM, and leaving the child as a
	 * zombie would keep a PID around that a later popup could be confused
	 * with. WNOHANG first so an already-exited child costs nothing; the short
	 * blocking wait is the common case and is bounded by how fast the menu
	 * tears its surface down. */
	if (waitpid(b->popup_pid, NULL, WNOHANG) == 0) {
		/* Still shutting down: give it a moment, but never block the bar for
		 * long - the UI must stay responsive. */
		for (int i = 0; i < 20; i++) {
			if (waitpid(b->popup_pid, NULL, WNOHANG) != 0)
				break;
			usleep(5000);   /* 5ms * 20 = 100ms max */
		}
	}
	b->popup_pid = 0;
	b->popup_region = -1;
}

/* Open `cmd` as the bar's popup, replacing or toggling as needed.
 *
 * `region` identifies the control that was clicked:
 *   - same region as the open popup  -> close it (a second click toggles)
 *   - different region               -> close the old, open the new
 *   - nothing open                   -> open
 */
static void
popup_toggle(Bar *b, int region, const char *cmd)
{
	int was_open = popup_alive(b);
	int same = was_open && b->popup_region == region;

	popup_close(b);

	if (same)
		return;               /* toggled off */

	if (!cmd || !*cmd)
		return;

	b->popup_pid = spawn_child(cmd);
	b->popup_region = b->popup_pid > 0 ? region : -1;
}

void
bar_handle_click(Bar *b, int x, int y, uint32_t button)
{
	for (int i = 0; i < b->region_count; i++) {
		HitRegion *r = &b->regions[i];

		if (x < r->x || x >= r->x + r->w || y < r->y || y >= r->y + r->h)
			continue;


		const char *cmd = NULL;

		/* Flash the press now: the command may open a window over the bar, so
		 * this is the only moment the feedback is visible. */
		b->pressed_region = i;
		b->pressed_until = now_ms() + 600;

		/* The click means the user has read the hint; hide it until the
		 * pointer leaves this control and comes back. */
		if (b->tip_region != -1) {
			b->tip_region = -1;
			tooltip_close(b);
		}
		b->tip_suppress = i;
		b->fb_x = r->x;
		b->fb_y = r->y;
		b->fb_w = r->w;
		b->fb_h = r->h;

		if (button == 0x110)        /* BTN_LEFT */
			cmd = r->left;
		else if (button == 0x112)   /* BTN_MIDDLE */
			cmd = r->middle;
		else if (button == 0x111)   /* BTN_RIGHT */
			cmd = r->right;

		if (cmd && *cmd) {
			/* Workspace switches go straight out without waiting. */
			if (strncmp(cmd, "swaymsg ", 8) == 0) {
				b->ws_fast_until = now_ms() + 2000;
				spawn(cmd);
			} else if (opens_menu(cmd)) {
				/* Menus are owned by the bar so a second click on the same
				 * control closes them, and clicking a different control swaps
				 * menus instead of stacking them. */
				popup_toggle(b, i, cmd);
			} else {
				spawn(cmd);
			}
		}
		bar_draw(b);
		return;
	}
}

/* ---- pointer listeners ------------------------------------------------ */
static void
ptr_enter(void *data, struct wl_pointer *p, uint32_t serial,
          struct wl_surface *surface, wl_fixed_t sx, wl_fixed_t sy)
{
	Bar *b = data;
	(void)p; (void)serial; (void)surface;


	b->wl.pointer_inside = 1;
	b->wl.pointer_x = wl_fixed_to_double(sx);
	b->wl.pointer_y = wl_fixed_to_double(sy);
}

static void
ptr_leave(void *data, struct wl_pointer *p, uint32_t serial,
          struct wl_surface *surface)
{
	Bar *b = data;
	(void)p; (void)serial; (void)surface;

	b->wl.pointer_inside = 0;

	if (b->tip_region != -1) {
		b->tip_region = -1;
		tooltip_close(b);
	}

	if (b->hover_region >= 0) {
		int was = b->hover_region;
		b->hover_region = -1;
		if (was < b->region_count) {
			HitRegion *r = &b->regions[was];
			b->hb_w = 0;
			b->hb_h = 0;
			(void)r;
		}
		bar_draw(b);
	}
}

static void
ptr_motion(void *data, struct wl_pointer *p, uint32_t time,
           wl_fixed_t sx, wl_fixed_t sy)
{
	Bar *b = data;
	(void)p; (void)time;

	int nx = wl_fixed_to_int(sx);
	int ny = wl_fixed_to_int(sy);
	int was = b->hover_region;

	b->wl.pointer_x = wl_fixed_to_double(sx);
	b->wl.pointer_y = wl_fixed_to_double(sy);
	b->hover_region = region_at(b, nx, ny);

	/* Keep the veil rectangle in step on every motion, not only on change:
	 * two writers would otherwise leave it stale. */
	if (b->hover_region >= 0) {
		HitRegion *r = &b->regions[b->hover_region];
		b->hb_x = r->x;
		b->hb_y = r->y;
		b->hb_w = r->w;
		b->hb_h = r->h;
	} else {
		b->hb_w = 0;
		b->hb_h = 0;
	}

	/* Tooltip follows the hovered control, and disappears the moment the
	 * pointer leaves the bar or lands on another window. A control that was
	 * just clicked keeps its tooltip hidden until the pointer leaves it. */
	{
		int want = (b->hover_region == b->tip_suppress) ? -1 : b->hover_region;

		if (want != b->tip_region) {
			b->tip_region = want;
			if (want >= 0 && want < b->region_count &&
			    b->regions[want].tip && b->regions[want].tip[0]) {
				HitRegion *hr = &b->regions[want];

				tooltip_show(b, hr->tip, hr->x, hr->w);
			} else {
				tooltip_close(b);
			}
		}
	}

	if (was != b->hover_region) {
		/* Repaint only the two pills involved. A full redraw re-runs every
		 * module including the centre title, and on the X11 bar that made the
		 * title blink as the pointer crossed the bar. */
		if (was >= 0 && was < b->region_count) {
			HitRegion *o = &b->regions[was];
			/* Restore from the baseline, then re-tint if needed. */
			if (b->baseline_valid) {
				cairo_save(b->cr);
				cairo_rectangle(b->cr, o->x, o->y, o->w, o->h);
				cairo_clip(b->cr);
				cairo_set_operator(b->cr, CAIRO_OPERATOR_SOURCE);
				cairo_set_source_surface(b->cr, b->baseline, 0, 0);
				cairo_paint(b->cr);
				cairo_set_operator(b->cr, CAIRO_OPERATOR_OVER);
				cairo_restore(b->cr);
			}
		}
		bar_draw(b);
	}
}

static void
ptr_button(void *data, struct wl_pointer *p, uint32_t serial, uint32_t time,
           uint32_t button, uint32_t state)
{
	Bar *b = data;
	(void)p; (void)serial; (void)time;


	if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
		b->wl.pointer_button = button;
		bar_handle_click(b, (int)b->wl.pointer_x, (int)b->wl.pointer_y, button);
	} else {
		b->wl.pointer_button = 0;
		if (b->pressed_region >= 0) {
			b->pressed_region = -1;
			bar_draw(b);
		}
	}
}

static void
ptr_axis(void *data, struct wl_pointer *p, uint32_t time, uint32_t axis,
         wl_fixed_t value)
{
	(void)data; (void)p; (void)time; (void)axis; (void)value;
}

/* wl_pointer v5+ frame/axis_source/axis_stop/axis_discrete; bind to version 5
 * so the compositor may send them, and accept them as no-ops. */
static void
ptr_frame(void *data, struct wl_pointer *p)
{
	(void)data; (void)p;
}

static void
ptr_axis_source(void *data, struct wl_pointer *p, uint32_t src)
{
	(void)data; (void)p; (void)src;
}

static void
ptr_axis_stop(void *data, struct wl_pointer *p, uint32_t time, uint32_t axis)
{
	(void)data; (void)p; (void)time; (void)axis;
}

static void
ptr_axis_discrete(void *data, struct wl_pointer *p, uint32_t axis, int32_t d)
{
	(void)data; (void)p; (void)axis; (void)d;
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = ptr_enter,
	.leave = ptr_leave,
	.motion = ptr_motion,
	.button = ptr_button,
	.axis = ptr_axis,
	.frame = ptr_frame,
	.axis_source = ptr_axis_source,
	.axis_stop = ptr_axis_stop,
	.axis_discrete = ptr_axis_discrete,
};

/* ---- keyboard: only for the URL-less shortcuts the bar needs ---------- */
static void
kbd_keymap(void *data, struct wl_keyboard *kb, uint32_t format, int32_t fd,
           uint32_t size)
{
	Bar *b = data;
	(void)kb;

	struct xkb_context *ctx = b->wl.xkb_ctx;

	if (!ctx)
		ctx = b->wl.xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);

	if (format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && ctx) {
		char *map = __builtin_alloca((size_t)size + 1);
		ssize_t n = read(fd, map, (size_t)size);

		if (n > 0) {
			map[n] = '\0';
			struct xkb_keymap *km = xkb_keymap_new_from_string(
			    ctx, map, XKB_KEYMAP_FORMAT_TEXT_V1,
			    XKB_KEYMAP_COMPILE_NO_FLAGS);
			if (km) {
				if (b->wl.xkb_state)
					xkb_state_unref(b->wl.xkb_state);
				if (b->wl.xkb_keymap)
					xkb_keymap_unref(b->wl.xkb_keymap);
				b->wl.xkb_keymap = km;
				b->wl.xkb_state = xkb_state_new(km);
			}
		}
	}
	close(fd);
}

static void
kbd_enter(void *data, struct wl_keyboard *kb, uint32_t serial,
          struct wl_surface *surface, struct wl_array *keys)
{
	(void)data; (void)kb; (void)serial; (void)surface; (void)keys;
}

static void
kbd_leave(void *data, struct wl_keyboard *kb, uint32_t serial,
          struct wl_surface *surface)
{
	(void)data; (void)kb; (void)serial; (void)surface;
}

static void
kbd_key(void *data, struct wl_keyboard *kb, uint32_t serial, uint32_t time,
        uint32_t key, uint32_t state)
{
	(void)data; (void)kb; (void)serial; (void)time; (void)key; (void)state;
}

static void
kbd_modifiers(void *data, struct wl_keyboard *kb, uint32_t serial,
              uint32_t dep, uint32_t lat, uint32_t lock, uint32_t group)
{
	Bar *b = data;
	(void)kb; (void)serial;

	if (b->wl.xkb_state)
		xkb_state_update_mask(b->wl.xkb_state, dep, lat, lock, 0, 0, group);
}

static void
kbd_repeat(void *data, struct wl_keyboard *kb, int32_t rate, int32_t delay)
{
	(void)data; (void)kb; (void)rate; (void)delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = kbd_keymap,
	.enter = kbd_enter,
	.leave = kbd_leave,
	.key = kbd_key,
	.modifiers = kbd_modifiers,
	.repeat_info = kbd_repeat,
};

/* wl_seat ------------------------------------------------------------- */
static void
seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps)
{
	Bar *b = data;

	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !b->wl.pointer) {
		b->wl.pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(b->wl.pointer, &pointer_listener, b);
	}
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !b->wl.keyboard) {
		b->wl.keyboard = wl_seat_get_keyboard(seat);
		wl_keyboard_add_listener(b->wl.keyboard, &keyboard_listener, b);
	}
}

static void
seat_name(void *data, struct wl_seat *seat, const char *name)
{
	(void)data; (void)seat; (void)name;
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
	.name = seat_name,
};

/* Called by wl.c's registry when a seat appears. */
/* The Bar being initialised, published for the registry callback.
 *
 * wl.c binds wl_seat inside the registry handler, and the capabilities event
 * arrives on the roundtrip that ends wl_init - so the listener has to be
 * attached right there, before wl_init returns. The callback only receives the
 * wl_seat, so the owning Bar is kept here. There is exactly one bar per
 * process, which is what makes a file-scope pointer acceptable. */
static Bar *g_bar;

void
bar_seat_attach(struct wl_seat *seat)
{
	if (seat && g_bar)
		wl_seat_add_listener(seat, &seat_listener, g_bar);
}

void bar_seat_setup(Bar *b);
void
bar_seat_setup(Bar *b)
{
	/* The listener was already attached by bar_seat_attach() when wl_seat was
	 * bound inside the registry callback. Only record the instance here; adding
	 * a second listener is an error ("proxy already has listener"). */
	g_bar = b;
}

/* =====================  main  ========================================== */

int
main(void)
{
	Bar b;
	unsigned long last_tick = 0;
	int wfd, ifd;

	memset(&b, 0, sizeof b);
	b.panel_alpha = load_opacity();
	b.hover_region = -1;
	b.popup_pid = 0;
	b.popup_region = -1;
	b.pressed_region = -1;
	b.tip_region = -1;
	b.tip_suppress = -1;
	b.wl.pointer_inside = 0;

	/* Width is decided by the compositor; start with the common case so the
	 * first buffer allocation has sensible dimensions.
	 *
	 * wl_init() blocks until the layer surface is configured, and it is that
	 * configure callback which allocates the shm buffer. So the cairo surface
	 * can only be created after it returns - binding cairo to shm_data before
	 * the first configure left it pointing at NULL, and every frame was drawn
	 * into memory the compositor never saw. */
	/* Publish the instance before wl_init: the registry callback binds wl_seat
	 * during that call and needs to attach the listener immediately. */
	g_bar = &b;

	if (wl_init(&b.wl, 1920, WINDOW_HEIGHT) != 0)
		return 1;

	if (!b.wl.shm_data) {
		fprintf(stderr, "bar: no shm buffer after configure\n");
		return 1;
	}

	bar_cairo_setup(&b);

	bar_seat_setup(&b);

	/* Force the seat's capabilities event to arrive now.
	 *
	 * wl_seat_add_listener only registers the callback; the compositor sends
	 * capabilities on the next flush/dispatch. The main loop below polls the
	 * fd itself and only calls wl_display_dispatch when the fd is readable, so
	 * without this roundtrip the pointer object was never created and the bar
	 * rendered fine but ignored every click and hover.
	 */
	if (wl_display_roundtrip(b.wl.dpy) < 0) {
		fprintf(stderr, "bar: seat roundtrip failed\n");
		return 1;
	}

	if (!b.wl.pointer)
		fprintf(stderr, "bar: no pointer device (clicks will not work)\n");

	b.ws_dirty = 1;
	bar_refresh(&b);
	bar_draw(&b);


	sway_subscribe();

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	wfd = wl_display_get_fd(b.wl.dpy);
	ifd = sway_fd();

	while (running && b.wl.configured > 0) {
		struct pollfd fds[2];
		int nfds = 0, rc;
		unsigned long t = now_ms();
		int timeout = (int)TICK_MS;

		fds[nfds].fd = wfd;
		fds[nfds].events = POLLIN;
		nfds++;
		if (ifd >= 0) {
			fds[nfds].fd = ifd;
			fds[nfds].events = POLLIN;
			nfds++;
		}

		rc = poll(fds, (nfds_t)nfds, timeout);
		if (rc > 0) {
			if (fds[0].revents & POLLIN) {
				if (wl_display_dispatch(b.wl.dpy) < 0)
					break;
			}
			if (nfds > 1 && (fds[1].revents & POLLIN)) {
				while (sway_pending())
					sway_read_event();
				b.ws_dirty = 1;

				/* A window event is exactly when the title changes, so read
				 * it now instead of waiting for the next sysinfo sample. The
				 * IPC round trip is one request and only happens on events. */
				if (refresh_title(&b))
					b.title_dirty = 1;
			}
		}

		t = now_ms();
		if (t - last_tick >= TICK_MS) {
			int ws_changed = b.ws_dirty;
			int cpu_before = b.cpu_count;
			int cpu_val_before = b.cpu_value;

			last_tick = t;
			bar_refresh(&b);

			/* Repaint on the graph's own cadence, like the X11 bar.
			 *
			 * The CPU line slides continuously: cpu_frac is the fraction of a
			 * sample interval elapsed, and the strip is drawn shifted by it.
			 * That only produces smooth motion if the frame is redrawn between
			 * samples - the sample itself arrives just four times a second.
			 *
			 * An earlier version repainted only when a new sample landed, so
			 * the line moved in 250ms jumps: 4Hz, which reads as stutter. The
			 * other two conditions are folded in rather than gating the draw,
			 * because the graph has to be redrawn every tick regardless.
			 *
			 * The right place for a narrower optimisation would be a partial
			 * repaint of the sysinfo band, which the X11 bar does with a clip;
			 * the whole bar is ~1600x46, so a full redraw at 30Hz is still
			 * cheap here and keeps the code honest. */
			(void)cpu_before;
			(void)cpu_val_before;

			if (ws_changed || b.title_dirty) {
				b.ws_dirty = 0;
				b.title_dirty = 0;
				bar_draw(&b);
			} else if (wl_frame_ready(&b.wl)) {
				/* Only draw when the compositor has already presented the
				 * previous frame. Drawing while it is still on screen just
				 * replaces a buffer the user never saw; the callback is what
				 * keeps us at exactly the display rate instead of guessing. */
				bar_draw_graph_only(&b);
			}
		}
	}

	/* Push any pending requests before tearing down. */
	wl_display_flush(b.wl.dpy);
	wl_finish(&b.wl);
	if (b.cr) cairo_destroy(b.cr);
	if (b.surface) cairo_surface_destroy(b.surface);
	if (b.baseline) cairo_surface_destroy(b.baseline);

	return 0;
}
