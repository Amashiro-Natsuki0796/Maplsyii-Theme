/* Wayland Everforest bar - shared definitions.
 *
 * This is a native Wayland rewrite of the X11 cairo bar (assets/bar-c). The
 * X11 version cannot run under sway: it samples the wallpaper with
 * XGetImage(RootWindow()), which XWayland refuses (BadMatch) because a Wayland
 * compositor never hands out root-window pixels.
 *
 * Layout of the program:
 *   wl.c      - protocol plumbing: registry, shm pool, layer surface, input
 *   draw.c    - cairo/pango drawing helpers (ported from bar-c)
 *   modules.c - the bar's modules (workspace pills, title, CPU graph, ...)
 *   bar.c     - state, main loop, event dispatch
 */
#pragma once

#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdbool.h>
#include <stdint.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "wlr-layer-shell-client.h"

/* ---- geometry (identical to the X11 bar so the layout matches) --------- */
#define BAR_HEIGHT      34
#define MARGIN_TOP      6
#define MARGIN_BOTTOM   6
#define MARGIN_SIDE     8
#define WINDOW_HEIGHT   (MARGIN_TOP + BAR_HEIGHT + MARGIN_BOTTOM)

#define PILL_RADIUS     9.0
#define PILL_PAD_X      11
#define PILL_MARGIN     4
#define PAD_SEP         2      /* box.mod-separator { padding: 0 2px } */
#define PAD_IME         9      /* box.mod-ime { padding: 0 9px } */
#define PAD_LAUNCHER    13     /* box.mod-launcher { padding: 0 13px } */
#define PAD_NOTIF       10     /* box.mod-notifications { padding: 0 10px } */
#define PAD_POWER       12     /* box.mod-power { padding: 0 12px } */
#define ICON_MIN_W      22     /* min-width for ime/launcher/notifications */
/* Wi-Fi arcs. The X11 bar strokes three concentric arcs instead of using one
 * font glyph, so the dot, the middle and the outer arc each carry their own
 * colour - that is the tricolour icon in the reference. */
#define WIFI_TOP        RGB(0x7d, 0xd6, 0xfb)   /* light blue, outer arc */
#define WIFI_MID        RGB(0xf4, 0xa7, 0xb9)   /* pink, middle arc */
#define WIFI_DOT        RGB(0xfe, 0xfe, 0xfe)   /* white dot */

#define R_LAUNCHER      13.0   /* the launcher pill's own radius */
#define R_NOTIF         15.0   /* box.mod-notifications { border-radius: 15px } */
#define R_POWER         10.0   /* box.mod-power { border-radius: 10px } */
#define PILL_MIN_HEIGHT 26

#define WS_PAD_X        5
#define WS_MARGIN_X     2
#define WS_MIN_W        29
#define WS_MIN_H        23
#define WS_RADIUS       11.0
#define LEFT_INSET      3

#define GRAPH_POINTS    40
#define GRAPH_WIDTH     46
#define GRAPH_HEIGHT    20
#define PAD_SYSINFO     12
#define SYSINFO_LABEL_PAD 5

/* The same font stack the X11 bar uses. The fallbacks matter: the Nerd Font
 * and Font Awesome faces supply the icon glyphs, and without them Pango picks
 * something wider, which is why the camera pill measured 37px here against
 * 45px on the X11 bar. */
#define FONT_STACK      "JetBrains Mono, Symbols Nerd Font, Font Awesome 6 Free, sans-serif"

#define FONT_SIZE       14
#define FONT_SIZE_SEP   16
#define FONT_WEIGHT     PANGO_WEIGHT_BOLD
#define FONT_WEIGHT_WS_ACTIVE PANGO_WEIGHT_HEAVY

/* Sentinel: pass as x to a module to measure without drawing. */
#define MEASURE_X       (-999999)

#define TICK_MS         33
#define TICK_SYSINFO_MS 250
#define TICK_CLOCK_MS   1000
#define TICK_NETWORK_MS 3000

/* ---- palette (Everforest, matching the X11 bar) ----------------------- */
#define RGB(r, g, b) ((double)(r) / 255.0), ((double)(g) / 255.0), ((double)(b) / 255.0)
#define C_BAR        RGB(0x17, 0x1b, 0x1c)
#define C_PILL       RGB(0x2f, 0x33, 0x36)
#define C_TEXT       RGB(0xd3, 0xc6, 0xaa)
#define C_CREAM      RGB(0xff, 0xfb, 0xef)
#define C_LIME       RGB(0xb9, 0xff, 0x66)
#define C_AMBER      RGB(0xff, 0xb0, 0x00)
#define C_LAUNCHER   RGB(0x00, 0xff, 0x00)
#define C_LAUNCHER_FG RGB(0x10, 0x24, 0x10)
#define C_NOTIF      RGB(0x7c, 0x7a, 0xff)
#define C_POWER      RGB(0xfa, 0x34, 0x33)
#define C_SEP        RGB(0x4a, 0x52, 0x50)
#define C_ALERT      RGB(0xe6, 0x7e, 0x80)
#define C_WHITE      RGB(0xff, 0xff, 0xff)
#define C_DARK_FG    RGB(0x17, 0x1b, 0x1c)

#define HOVER_ALPHA   0.10
#define PRESS_ALPHA   0.18
#define PANEL_RADIUS  12.0

/* Transparency presets, matching the i3 rice's bar.json values so the two
 * desktops look the same. Selected by $BAR_WL_OPACITY, else "solid". */
#define OPACITY_SOLID 1.00
#define OPACITY_SOFT  0.82
#define OPACITY_CLEAR 0.35

/* ---- protocol globals we care about ---------------------------------- */
struct wl_state {
	struct wl_display *dpy;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct wl_seat *seat;
	struct wl_pointer *pointer;
	struct wl_keyboard *keyboard;
	struct zwlr_layer_shell_v1 *layer_shell;

	/* One surface; the bar only ever has one. */
	struct wl_surface *surface;
	struct zwlr_layer_surface_v1 *layer_surface;
	struct wl_buffer *buffer;
	void *shm_data;
	size_t shm_size;

	int width;          /* surface width in px, from the compositor */
	int height;         /* WINDOW_HEIGHT */
	int configured;

	/* Frame throttling: a callback is armed after each commit and the next
	 * frame is only submitted once the compositor says it is ready. */
	struct wl_callback *frame_cb;
	int frame_ready;

	struct xkb_context *xkb_ctx;
	struct xkb_keymap *xkb_keymap;
	struct xkb_state *xkb_state;

	/* Pointer state, absolute surface coordinates. */
	double pointer_x, pointer_y;
	int pointer_inside;
	uint32_t pointer_button;   /* button currently held, 0 = none */
};

/* ---- click regions (ported from the X11 bar) ------------------------- */
typedef struct {
	int x, y, w, h;
	char *left;      /* command for button 1 */
	char *middle;    /* button 2 */
	char *right;     /* button 3 */
	char *tip;       /* tooltip text */
} HitRegion;

typedef struct {
	unsigned long long total, idle;
	int valid;
} CpuSample;

typedef struct {
	int num;
	int focused;
	int urgent;
} WsInfo;

/* Full bar state. */
typedef struct {
	struct wl_state wl;

	cairo_surface_t *surface;
	cairo_t *cr;
	cairo_surface_t *baseline;
	int baseline_valid;

	HitRegion regions[64];
	int region_count;

	int hover_region;
	int pressed_region;
	unsigned long pressed_until;
	int hb_x, hb_y, hb_w, hb_h;   /* hover veil rect */
	int fb_x, fb_y, fb_w, fb_h;   /* press veil rect */

	/* sysinfo band, repainted on its own cadence */
	int graph_x, graph_y, graph_w, graph_h;
	int plot_x, plot_y, plot_w, plot_h;
	int graph_dirty;

	/* modules */
	WsInfo ws[16];
	int ws_count;
	unsigned long ws_sig;
	int ws_dirty;

	char title[512];
	char clock[16];
	char date[64];
	int memory_pct;

	int cpu_history[GRAPH_POINTS];
	int cpu_count;
	int cpu_value;
	double cpu_frac;
	unsigned long cpu_last_ms;
	unsigned long long prev_total, prev_idle;
	int cpu_seen;

	int network_connected;
	int network_is_wifi;   /* 1 = wireless, 0 = wired */
	int notifications_count;
	int notifications_dnd;
	int ime_active;

	double panel_alpha;

	int tip_region;      /* region whose tooltip is open, -1 = none */
	int tip_suppress;    /* region whose tooltip was just dismissed */

	unsigned long last_ws, last_clock, last_sysinfo, last_network;
	unsigned long ws_fast_until;

	/* Set when the focused window's title changed; cleared by the draw loop.
	 * A title change is invisible to the other repaint triggers: switching
	 * between two windows in the same workspace changes neither the workspace
	 * list nor the CPU graph. */
	int title_dirty;

	/* The popup this bar opened, if any.
	 *
	 * wofi/rofi run as their own processes and take an exclusive keyboard grab,
	 * so the bar cannot see whether one is open. Tracking the child lets a
	 * second click on the same control close it, and a click on a different
	 * control replace it - without that, every click stacked another menu. */
	pid_t popup_pid;      /* process group leader, 0 = none */
	int popup_region;     /* which control opened it, -1 = none */
} Bar;

/* ---- cross-file API --------------------------------------------------- */
/* wl.c */
int  wl_init(struct wl_state *w, int width, int height);
int  wl_create_buffer(struct wl_state *w);
void wl_commit(struct wl_state *w);
void wl_commit_rect(struct wl_state *w, int x, int y, int width, int height);
int  wl_frame_ready(struct wl_state *w);
int  wl_dispatch(struct wl_state *w, int timeout_ms);
void wl_finish(struct wl_state *w);

/* draw.c */
void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r);
void draw_panel(Bar *b);
void draw_pill(Bar *b, int x, int y, int w, int h, double cr_, double cg, double cb);
void draw_pill_r(Bar *b, int x, int y, int w, int h, double radius,
                 double r, double g, double bl);
void draw_text(Bar *b, int x, int y, const char *utf8, double r, double g, double bl);
void draw_text_n(Bar *b, int x, int y, const char *utf8, int size, int weight,
                 double r, double g, double bl);
void draw_text_in(Bar *b, int x, int y, int h, const char *utf8, int size,
                  int weight, double r, double g, double bl);
int  text_width(Bar *b, const char *utf8);
int  text_width_sized(Bar *b, const char *utf8, int size, int weight);
void draw_feedback(Bar *b, int x, int y, int w, int h, double radius, double alpha);
void draw_ethernet(Bar *b, int x, int y, int w, int h,
               double r, double g, double bl);
void draw_wifi(Bar *b, int x, int y, int w, int h,
               double r_top, double g_top, double bl_top,
               double r_mid, double g_mid, double bl_mid,
               double r_dot, double g_dot, double bl_dot);

/* modules.c */
int  module_workspaces(Bar *b, int x, int y, int h);
int  module_separator(Bar *b, int x, int y, int h);
int  module_screenshot(Bar *b, int x, int y, int h);
int  module_ime(Bar *b, int x, int y, int h);
int  module_sysinfo(Bar *b, int x, int y, int h);
int  module_launcher(Bar *b, int x, int y, int h);
int  module_notifications(Bar *b, int x, int y, int h);
int  module_power(Bar *b, int x, int y, int h);
int  module_clock(Bar *b, int x, int y, int h);
int  module_network(Bar *b, int x, int y, int h);
int  module_window(Bar *b, int x, int y, int h, int max_w);
void module_draw_cpu_graph(Bar *b, int x, int y, int w, int h);
void sysinfo_outline(Bar *b, int x, int y, int w, int h);
void bar_draw_graph_only(Bar *b);

/* bar.c helpers shared with modules */
void add_region(Bar *b, int x, int y, int w, int h,
                const char *left, const char *middle, const char *right);
void set_region_tip(Bar *b, const char *tip);
void  spawn(const char *cmd);
pid_t spawn_child(const char *cmd);
unsigned long now_ms(void);

/* sway IPC */
int  sway_get_workspaces(char *out, size_t outsz);
int  sway_subscribe(void);
int  sway_fd(void);
int  sway_pending(void);
void sway_read_event(void);
int  sway_get_active_app(char *out, size_t outsz, char *cls, size_t clssz);

/* tooltip.c */
void tooltip_show(Bar *b, const char *text, int x, int w);
void tooltip_close(Bar *b);
