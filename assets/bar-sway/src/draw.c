/* cairo/pango drawing helpers, ported from the X11 bar (assets/bar-c/src/draw.c).
 *
 * Kept deliberately identical in behaviour: same rounded-rectangle maths, same
 * pill geometry, same font stack. Only the surface underneath changed - a
 * wl_shm image here, an Xlib surface there - so the visual result matches.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "bar.h"

/* Rounded rectangle path. Two arcs per corner, with the radius clamped so a
 * small pill does not produce a self-intersecting path. */
void
rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r)
{
	double maxr = (w < h ? w : h) / 2.0;

	if (r > maxr)
		r = maxr;
	if (r < 0)
		r = 0;

	cairo_new_sub_path(cr);
	cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
	cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
	cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
	cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
	cairo_close_path(cr);
}

/* The panel itself: transparent margin, one rounded strip in the bar colour.
 *
 * The X11 version sampled the wallpaper column-by-column so the translucent
 * strip would match what was behind it. That cannot work here - a Wayland
 * client has no way to read the screen - and it is not needed either: the
 * compositor blends the alpha channel against the real desktop. This is
 * simpler and more correct than the sampling code was.
 */
void
draw_panel(Bar *b)
{
	cairo_t *cr = b->cr;

	cairo_save(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_restore(cr);

	rounded_rect(cr, MARGIN_SIDE, MARGIN_TOP,
	             b->wl.width - 2 * MARGIN_SIDE, BAR_HEIGHT, PANEL_RADIUS);
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, C_BAR, b->panel_alpha);
	cairo_fill(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
}

void
draw_pill_r(Bar *b, int x, int y, int w, int h, double radius,
            double r, double g, double bl)
{
	cairo_t *cr = b->cr;

	rounded_rect(cr, x, y, w, h, radius);
	cairo_set_source_rgb(cr, r, g, bl);
	cairo_fill(cr);
}

void
draw_pill(Bar *b, int x, int y, int w, int h, double r, double g, double bl)
{
	draw_pill_r(b, x, y, w, h, PILL_RADIUS, r, g, bl);
}

/* Cached PangoFontDescription per (size, weight).
 *
 * Building one costs a string copy of the family plus a full description
 * hash - measurable when the graph band redraws 30 times a second. There are
 * only a handful of distinct (size, weight) pairs in the whole bar, so they
 * are built once.
 */
struct font_key {
	int size;
	int weight;
	PangoFontDescription *desc;
};

static struct font_key font_cache[8];
static int font_cache_n;

static PangoFontDescription *
font_desc(int size, int weight)
{
	for (int i = 0; i < font_cache_n; i++)
		if (font_cache[i].size == size && font_cache[i].weight == weight)
			return font_cache[i].desc;

	if (font_cache_n >= (int)(sizeof font_cache / sizeof font_cache[0]))
		return NULL;

	PangoFontDescription *d = pango_font_description_new();

	pango_font_description_set_family(d, FONT_STACK);
	pango_font_description_set_absolute_size(d, size * PANGO_SCALE);
	pango_font_description_set_weight(d, weight);
	font_cache[font_cache_n].size = size;
	font_cache[font_cache_n].weight = weight;
	font_cache[font_cache_n].desc = d;
	font_cache_n++;
	return d;
}

/* One reusable layout, re-pointed at the current cairo context.
 *
 * pango_cairo_create_layout() allocates a layout bound to a cairo_t; our cairo
 * context survives for the whole run, so the layout can too. Only the text and
 * the font description change per call, and both are cheap to set. */
static PangoLayout *reusable_layout;

static PangoLayout *
make_layout(Bar *b, const char *utf8, int size, int weight)
{
	PangoFontDescription *d;

	if (!reusable_layout)
		reusable_layout = pango_cairo_create_layout(b->cr);

	d = font_desc(size, weight);
	if (d)
		pango_layout_set_font_description(reusable_layout, d);
	pango_layout_set_text(reusable_layout, utf8, -1);
	pango_layout_set_single_paragraph_mode(reusable_layout, TRUE);
	return reusable_layout;
}

int
text_width(Bar *b, const char *utf8)
{
	return text_width_sized(b, utf8, FONT_SIZE, FONT_WEIGHT);
}

/* Width of `utf8` at a specific size/weight. The separator needs this: it is
 * the one module whose glyph is drawn larger and lighter than the rest. */
int
text_width_sized(Bar *b, const char *utf8, int size, int weight)
{
	PangoLayout *l = make_layout(b, utf8, size, weight);
	int w, h;

	pango_layout_get_pixel_size(l, &w, &h);
	return w;
}

void
draw_text_n(Bar *b, int x, int y, const char *utf8, int size, int weight,
            double r, double g, double bl)
{
	PangoLayout *l = make_layout(b, utf8, size, weight);
	int tw, th;

	pango_layout_get_pixel_size(l, &tw, &th);
	cairo_set_source_rgb(b->cr, r, g, bl);
	cairo_move_to(b->cr, x, y + (BAR_HEIGHT - th) / 2.0);
	pango_cairo_show_layout(b->cr, l);
}

void
draw_text(Bar *b, int x, int y, const char *utf8, double r, double g, double bl)
{
	draw_text_n(b, x, y, utf8, FONT_SIZE, FONT_WEIGHT, r, g, bl);
}

/* Text centred vertically inside a box (a pill), not inside the whole bar. */
void
draw_text_in(Bar *b, int x, int y, int h, const char *utf8, int size,
             int weight, double r, double g, double bl)
{
	PangoLayout *l = make_layout(b, utf8, size, weight);
	int tw, th;

	pango_layout_get_pixel_size(l, &tw, &th);
	cairo_set_source_rgb(b->cr, r, g, bl);
	cairo_move_to(b->cr, x, y + (h - th) / 2.0);
	pango_cairo_show_layout(b->cr, l);
}

/* Hover/press veil: a translucent rounded rectangle over the whole pill. */
void
draw_feedback(Bar *b, int x, int y, int w, int h, double radius, double alpha)
{
	cairo_t *cr = b->cr;

	cairo_save(cr);
	rounded_rect(cr, x, y, w, h, radius);
	cairo_set_source_rgba(cr, 1, 1, 1, alpha);
	cairo_fill(cr);
	cairo_restore(cr);
}

/* Wi-Fi symbol: three concentric arcs with equal spacing between neighbours,
 * each stroked in its own colour. Ported verbatim from the X11 bar - the
 * geometry is chosen so the outer arc fills the box and the dot stays ~4px
 * across, which is what makes the icon read at this size. */
void
draw_wifi(Bar *b, int x, int y, int w, int h,
          double r_top, double g_top, double bl_top,
          double r_mid, double g_mid, double bl_mid,
          double r_dot, double g_dot, double bl_dot)
{
	cairo_t *cr = b->cr;
	double cx = x + w / 2.0;
	double R = w * 0.47;
	double P = (R - 1.9) / 2.0;
	double r_outer = R;
	double r_middle = R - P;
	double dot_r = R - 2.0 * P;
	double base = y + h / 2.0 - (dot_r - r_outer) / 2.0;

	cairo_set_line_width(cr, 2.0);
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);

	cairo_new_path(cr);
	cairo_arc(cr, cx, base, r_middle, M_PI * 1.20, M_PI * 1.80);
	cairo_set_source_rgb(cr, r_mid, g_mid, bl_mid);
	cairo_stroke(cr);

	cairo_new_path(cr);
	cairo_arc(cr, cx, base, r_outer, M_PI * 1.20, M_PI * 1.80);
	cairo_set_source_rgb(cr, r_top, g_top, bl_top);
	cairo_stroke(cr);

	cairo_arc(cr, cx, base, dot_r, 0, 2 * M_PI);
	cairo_set_source_rgb(cr, r_dot, g_dot, bl_dot);
	cairo_fill(cr);
	(void)h;
}

/* Wired-network symbol: an RJ45 socket with a plug seated in it.
 *
 * The port is the wide rectangle; the small block above it is the connector
 * going in. That reads as "Ethernet" at 18px in a way a bare socket does not,
 * because the plug gives the shape a direction - the eye sees something being
 * inserted rather than an empty box.
 *
 * Drawn in the same 18x14 box the wifi arcs occupy, so the pill keeps its width
 * and the bar's right-hand layout does not shift with the hardware present.
 */
void
draw_ethernet(Bar *b, int x, int y, int w, int h,
              double r, double g, double bl)
{
	cairo_t *cr = b->cr;
	double cx = x + w / 2.0;
	double bw = w * 0.86;               /* port width */
	double bh = h * 0.56;               /* port height */
	double bx = cx - bw / 2.0;
	double by = y + h * 0.30;           /* port sits low, plug above it */
	double nw = bw * 0.30;              /* latch notch width */
	double nd = bh * 0.34;              /* latch notch depth */
	double pw = bw * 0.42;              /* plug width */
	double ph = h * 0.22;               /* plug height */

	cairo_set_source_rgb(cr, r, g, bl);
	cairo_set_line_width(cr, 1.5);
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);

	/* Port opening. */
	cairo_new_path(cr);
	cairo_rectangle(cr, bx, by, bw, bh);
	cairo_stroke(cr);

	/* Latch notch on the bottom edge. */
	cairo_new_path(cr);
	cairo_move_to(cr, cx - nw / 2, by + bh);
	cairo_line_to(cr, cx - nw / 2, by + bh - nd);
	cairo_line_to(cr, cx + nw / 2, by + bh - nd);
	cairo_line_to(cr, cx + nw / 2, by + bh);
	cairo_stroke(cr);

	/* Plug seated above the port. */
	cairo_new_path(cr);
	cairo_rectangle(cr, cx - pw / 2, by - ph, pw, ph);
	cairo_stroke(cr);

	/* Its two contacts. */
	cairo_new_path(cr);
	cairo_move_to(cr, cx - pw * 0.22, by);
	cairo_line_to(cr, cx - pw * 0.22, by - ph * 0.5);
	cairo_move_to(cr, cx + pw * 0.22, by);
	cairo_line_to(cr, cx + pw * 0.22, by - ph * 0.5);
	cairo_stroke(cr);
}
