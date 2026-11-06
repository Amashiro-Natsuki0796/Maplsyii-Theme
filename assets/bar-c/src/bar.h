/* Shared declarations for the C bar. */
#ifndef EF_BAR_H
#define EF_BAR_H

#include <X11/Xlib.h>
#include <cairo/cairo.h>
#include <cairo/cairo-xlib.h>
#include <pango/pangocairo.h>

#include "config.h"

/* One clickable region. The three commands map to buttons 1/2/3. */
typedef struct {
	int x, y, w, h;
	char *left;
	char *middle;
	char *right;
	char *tip;      /* hover tooltip text, English */
} HitRegion;

#define MAX_REGIONS 32

/* Cached values, refreshed on their own timers. */
typedef struct {
	char memory[32];
	char cpu_history[GRAPH_POINTS];
	int cpu_len;
	int cpu_value;
	unsigned long cpu_seq;   /* bumps on every sample */
	double cpu_frac;         /* 0..1 progress toward the next sample */
	unsigned long cpu_last_ms;
	double cpu_interval_ms;  /* measured gap between samples, see refresh_cpu */
	int network_connected;
	char clock[16];
	char date[64];
	/* Active-window title, cached.
	 *
	 * module_window() used to fork `xdotool getactivewindow getwindowname` on
	 * every bar_draw(). Hovering a control triggers a full bar_draw(), so every
	 * pointer move into the bar re-ran that fork; while it was in flight the
	 * capture could come back empty and the centre title vanished for a frame -
	 * the "title flickers on hover" bug. Caching it removes both the fork and
	 * the flicker. */
	char wintitle[512];
	Window winid;
	int ws_count;
	struct {
		int num;
		int focused;
		int urgent;
	} ws[16];
} State;

typedef struct {
	Display *dpy;
	Window win;
	Window input;   /* transparent overlay that receives clicks */
	int screen;
	int width;
	Visual *visual;
	Colormap cmap;
	int depth;
	cairo_surface_t *surface;
	cairo_t *cr;

	HitRegion regions[MAX_REGIONS];
	int region_count;

	State st;

	/* Panel alpha, from bar.json's "opacity" preset. */
	double panel_alpha;
	double panel_base;      /* configured alpha for the current preset */
	unsigned long last_layout;
	unsigned long ws_fast_until;
	int ws_dirty;   /* workspace state changed, needs a full repaint */
	unsigned long ws_sig;   /* signature of num+focused+urgent per workspace */
	unsigned long last_clock;
	unsigned long last_sysinfo;
	unsigned long last_network;
	int last_ws_count;
	unsigned long last_ws;

	/* The realtime band: memory text plus the CPU graph. The fast path
	 * repaints this every frame, so it covers the whole sysinfo pill. */
	int graph_x, graph_y, graph_w, graph_h;
	/* The graph's own rectangle inside that band. */
	int plot_x, plot_y, plot_w, plot_h;

	/* Baseline image of the bar without any hover/press veil. Hover repaints
	 * restore from here instead of re-running every module. */
	cairo_surface_t *baseline;
	int baseline_valid;

	/* Pointer feedback. hover_region is matched on every motion event;
	 * pressed_region is set while a button is held. */
	int hover_region;
	int pressed_region;
	int tip_region;   /* region whose tooltip is on screen */
	int tip_suppress; /* region clicked; do not show its tooltip
	                   * again until the pointer leaves it */
	/* Geometry of the pressed/hovered region, captured before free_regions()
	 * clears the list on the next draw. */
	int fb_x, fb_y, fb_w, fb_h;
	unsigned long pressed_until;
	int hb_x, hb_y, hb_w, hb_h;   /* hovered rect, cached per frame */
	int pointer_x, pointer_y;

	/* Colour sampled behind the bar, one entry per horizontal step, so the
	 * panel blends with the wallpaper exactly where it is. */
	double under_r[64], under_g[64], under_b[64];
	int under_n;
} Bar;

/* bar.c */
void bar_init(Bar *b);
void bar_draw(Bar *b);
void bar_sample_under(Bar *b);
void bar_draw_graph_only(Bar *b);
void bar_draw_region_only(Bar *b, int rx, int ry, int rw, int rh);
void bar_update_hover(Bar *b);
void bar_handle_click(Bar *b, int x, int y, int button);
void bar_handle_motion(Bar *b, int x, int y);
void bar_handle_release(Bar *b, int x, int y);
void bar_refresh(Bar *b);

/* modules.c - returns the width consumed; MEASURE_X means measure only */
int module_workspaces(Bar *b, int x, int y, int h);
int module_window(Bar *b, int x, int y, int h, int max_w);
int module_separator(Bar *b, int x, int y, int h);
int module_screenshot(Bar *b, int x, int y, int h);
int module_ime(Bar *b, int x, int y, int h);
int module_sysinfo(Bar *b, int x, int y, int h);
void module_draw_cpu_graph(Bar *b, int x, int y, int w, int h);
void module_draw_cpu_graph_at(Bar *b, cairo_t *cr, int x, int y, int w, int h);
int module_launcher(Bar *b, int x, int y, int h);
int module_notifications(Bar *b, int x, int y, int h);
int module_power(Bar *b, int x, int y, int h);
int module_clock(Bar *b, int x, int y, int h);
int module_network(Bar *b, int x, int y, int h);

/* draw.c */
void draw_panel(Bar *b);
void draw_pill(Bar *b, int x, int y, int w, int h, double r, double g, double bl);
void draw_pill_r(Bar *b, int x, int y, int w, int h, double radius,
                 double r, double g, double bl);
void draw_text(Bar *b, int x, int y, const char *text, double r, double g, double bl);
void sysinfo_outline(Bar *b, int bx, int by, int w, int bh);
void draw_text_in(Bar *b, int x, int y, int box_h, const char *text,
                  double size, int weight, double r, double g, double bl);
void draw_text_n(Bar *b, int x, int y, const char *text, double size, int weight,
                 double r, double g, double bl);
void draw_wifi(Bar *b, int x, int y, int w, int h, double r_top, double g_top, double bl_top, double r_mid, double g_mid, double bl_mid, double r_dot, double g_dot, double bl_dot);
void draw_feedback(Bar *b, int x, int y, int w, int h, double radius, double alpha);
int text_width(Bar *b, const char *text);
int text_width_sized(Bar *b, const char *text, double size, int weight);

/* util.c */
void spawn(const char *cmd);
int  i3_get_workspaces(char *out, size_t outsz);
int  i3_subscribe(void);
int  i3_fd_get(void);
int  i3_pending(void);
void i3_read_event(void);
void set_region_tip(Bar *b, const char *tip);
void tooltip_show(Bar *b, const char *text, int x, int w);
void tooltip_close(Bar *b);
void add_region(Bar *b, int x, int y, int w, int h,
                const char *left, const char *middle, const char *right);
void free_regions(Bar *b);

#endif
