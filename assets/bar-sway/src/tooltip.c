/* Hover tooltip: a second layer surface that pops under the hovered control.
 *
 * The X11 bar creates an override-redirect ARGB window for this. Wayland has
 * no such thing, so the tooltip is a layer surface of its own, anchored to the
 * top-left, positioned with set_margin() from the bar's own geometry.
 *
 * The surface is created on demand and destroyed on leave: keeping a mapped
 * surface around would hold a compositor buffer for something that is only
 * visible while the pointer rests on a pill.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "bar.h"

#define TIP_PAD_X   10
#define TIP_PAD_Y   7
#define TIP_RADIUS  7.0
#define TIP_GAP     6      /* distance below the bar */
#define TIP_MAX_W   420

struct tip_state {
	Bar *bar;

	struct wl_surface *surface;
	struct zwlr_layer_surface_v1 *layer;
	struct wl_buffer *buffer;
	void *data;
	size_t size;

	int width, height;
	int configured;
	int mapped;

	int want_x, want_y, want_w, want_h;
	char text[1024];
};

static struct tip_state tip;
static int tip_in_use;

static void
tip_configure(void *data, struct zwlr_layer_surface_v1 *ls,
              uint32_t serial, uint32_t width, uint32_t height)
{
	struct tip_state *t = data;

	(void)width; (void)height;
	zwlr_layer_surface_v1_ack_configure(ls, serial);
	t->configured = 1;
}

static void
tip_closed(void *data, struct zwlr_layer_surface_v1 *ls)
{
	struct tip_state *t = data;

	(void)ls;
	t->configured = -1;
}

static const struct zwlr_layer_surface_v1_listener tip_listener = {
	.configure = tip_configure,
	.closed = tip_closed,
};

static int
tip_alloc(struct tip_state *t)
{
	int stride = t->width * 4;

	t->size = (size_t)stride * t->height;

	/* memfd via the runtime dir, same approach as the bar's own buffer. */
	char name[256];
	int fd;

	snprintf(name, sizeof name, "%s/bar-wl-tip-XXXXXX",
	         getenv("XDG_RUNTIME_DIR") ? getenv("XDG_RUNTIME_DIR") : "/tmp");
	fd = mkstemp(name);
	if (fd < 0)
		return -1;
	unlink(name);
	if (ftruncate(fd, (off_t)t->size) < 0) {
		close(fd);
		return -1;
	}
	t->data = mmap(NULL, t->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (t->data == MAP_FAILED) {
		t->data = NULL;
		close(fd);
		return -1;
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(t->bar->wl.shm, fd, (int32_t)t->size);
	t->buffer = wl_shm_pool_create_buffer(pool, 0, t->width, t->height,
	                                     stride, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	return 0;
}

/* Measure the text and work out the box. Returns 0 when there is nothing to
 * show (empty text). */
static int
tip_measure(struct tip_state *t, const char *text, int anchor_x, int anchor_w)
{
	Bar *b = t->bar;
	int screen_w = b->wl.width;
	int lines = 1;
	int tw = 0;

	for (const char *p = text; *p; p++)
		if (*p == '\n')
			lines++;

	/* Width of the longest line. */
	{
		char buf[1024];
		snprintf(buf, sizeof buf, "%s", text);
		char *line = buf;

		while (line && *line) {
			char *nl = strchr(line, '\n');
			if (nl)
				*nl = '\0';
			{
				int w = text_width(b, line);
				if (w > tw)
					tw = w;
			}
			line = nl ? nl + 1 : NULL;
		}
	}
	if (tw == 0)
		return 0;

	int box_w = tw + 2 * TIP_PAD_X;
	int box_h = lines * 18 + 2 * TIP_PAD_Y;

	if (box_w > TIP_MAX_W)
		box_w = TIP_MAX_W;

	/* Centre under the control, then keep it on screen. */
	int box_x = anchor_x + anchor_w / 2 - box_w / 2;
	if (box_x < 4)
		box_x = 4;
	if (box_x + box_w > screen_w - 4)
		box_x = screen_w - 4 - box_w;

	t->want_x = box_x;
	t->want_y = WINDOW_HEIGHT + TIP_GAP;
	t->want_w = box_w;
	t->want_h = box_h;
	snprintf(t->text, sizeof t->text, "%s", text);
	return 1;
}

static void
tip_render(struct tip_state *t)
{
	Bar *b = t->bar;
	cairo_surface_t *surf;
	cairo_t *cr;
	int stride = t->width * 4;

	surf = cairo_image_surface_create_for_data(t->data, CAIRO_FORMAT_ARGB32,
	                                           t->width, t->height, stride);
	/* Both objects report failure through a status instead of returning NULL.
	 * Nothing may be drawn once either is in an error state - cairo would run
	 * the operations against an invalid surface, which is exactly the kind of
	 * invalid write pixman then faults on. */
	if (!surf || cairo_surface_status(surf) != CAIRO_STATUS_SUCCESS) {
		if (surf)
			cairo_surface_destroy(surf);
		return;
	}

	cr = cairo_create(surf);
	if (!cr || cairo_status(cr) != CAIRO_STATUS_SUCCESS) {
		if (cr)
			cairo_destroy(cr);
		cairo_surface_destroy(surf);
		return;
	}

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Panel. */
	rounded_rect(cr, 0.5, 0.5, t->width - 1, t->height - 1, TIP_RADIUS);
	cairo_set_source_rgba(cr, 0x1e / 255.0, 0x23 / 255.0, 0x26 / 255.0, 0.96);
	cairo_fill_preserve(cr);
	cairo_set_source_rgba(cr, 0x4a / 255.0, 0x52 / 255.0, 0x50 / 255.0, 0.9);
	cairo_set_line_width(cr, 1.0);
	cairo_stroke(cr);

	/* Text, one line at a time. */
	{
		char buf[1024];
		snprintf(buf, sizeof buf, "%s", t->text);
		char *line = buf;
		int ly = TIP_PAD_Y;

		cairo_t *save = b->cr;
		b->cr = cr;      /* draw_text_in uses b->cr */

		while (line && *line) {
			char *nl = strchr(line, '\n');
			if (nl)
				*nl = '\0';
			draw_text_n(b, TIP_PAD_X, ly - MARGIN_TOP, line,
			            12, PANGO_WEIGHT_NORMAL, C_TEXT);
			ly += 18;
			line = nl ? nl + 1 : NULL;
		}
		b->cr = save;
	}

	cairo_surface_flush(surf);
	cairo_destroy(cr);
	cairo_surface_destroy(surf);
}

void
tooltip_show(Bar *b, const char *text, int x, int w)
{
	if (!text || !*text) {
		tooltip_close(b);
		return;
	}

	if (!tip_in_use) {
		memset(&tip, 0, sizeof tip);
		tip.bar = b;

		tip.surface = wl_compositor_create_surface(b->wl.compositor);
		if (!tip.surface)
			return;
		tip.layer = zwlr_layer_shell_v1_get_layer_surface(
		    b->wl.layer_shell, tip.surface, NULL,
		    ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "i3-everforest-tooltip");
		zwlr_layer_surface_v1_add_listener(tip.layer, &tip_listener, &tip);

		zwlr_layer_surface_v1_set_anchor(tip.layer,
		                                 ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
		                                 ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
		zwlr_layer_surface_v1_set_keyboard_interactivity(
		    tip.layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
		/* Never reserve space for a tooltip. */
		zwlr_layer_surface_v1_set_exclusive_zone(tip.layer, 0);
		tip_in_use = 1;
	}

	if (!tip_measure(&tip, text, x, w))
		return;

	zwlr_layer_surface_v1_set_size(tip.layer, (uint32_t)tip.want_w,
	                               (uint32_t)tip.want_h);
	zwlr_layer_surface_v1_set_margin(tip.layer, tip.want_y, 0, 0, tip.want_x);
	wl_surface_commit(tip.surface);
	wl_display_flush(b->wl.dpy);

	/* Wait for configure before attaching a buffer: the compositor may adjust
	 * the size, and attaching first would race that. */
	while (tip.configured == 0) {
		if (wl_display_dispatch(b->wl.dpy) < 0)
			return;
	}
	if (tip.configured < 0)
		return;

	tip.width = tip.want_w;
	tip.height = tip.want_h;
	if (!tip.buffer && tip_alloc(&tip) != 0)
		return;

	tip_render(&tip);

	wl_surface_attach(tip.surface, tip.buffer, 0, 0);
	wl_surface_damage_buffer(tip.surface, 0, 0, tip.width, tip.height);
	wl_surface_commit(tip.surface);
	wl_display_flush(b->wl.dpy);
	tip.mapped = 1;
}

void
tooltip_close(Bar *b)
{
	(void)b;

	if (!tip_in_use)
		return;

	if (tip.buffer) {
		wl_buffer_destroy(tip.buffer);
		tip.buffer = NULL;
	}
	if (tip.data) {
		munmap(tip.data, tip.size);
		tip.data = NULL;
	}
	if (tip.layer) {
		zwlr_layer_surface_v1_destroy(tip.layer);
		tip.layer = NULL;
	}
	if (tip.surface) {
		wl_surface_destroy(tip.surface);
		tip.surface = NULL;
	}
	tip.configured = 0;
	tip.mapped = 0;
	tip_in_use = 0;
}
