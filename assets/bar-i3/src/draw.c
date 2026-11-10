/* Cairo primitives: rounded rectangles, pills and text.
 *
 * Each function takes an explicit radius and colour because the CSS gives
 * individual modules their own values (notifications 15px, power 10px, the
 * rest 9px). */
#include <math.h>
#include <string.h>
#include <pango/pangocairo.h>

#include "bar.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static void
rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r)
{
	if (r > h / 2) r = h / 2;
	if (r > w / 2) r = w / 2;
	cairo_new_sub_path(cr);
	cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
	cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
	cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
	cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
	cairo_close_path(cr);
}

/* The panel: a rounded strip inset by MARGIN_SIDE, transparent everywhere
 * else so the wallpaper shows through the margins exactly as before. */
void
draw_panel(Bar *b)
{
	cairo_t *cr = b->cr;

	/* Clear to fully transparent first, so the rounded corners let the
	 * wallpaper through - the GTK version relied on an ARGB visual for this,
	 * which cairo gives us on the same 24-bit window via the compositor. */
	cairo_save(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_restore(cr);

	/* The strip itself, with real alpha.
	 *
	 * Sampling the wallpaper and blending by hand cannot work: X composites
	 * child windows into root reads, so inside the strip we only ever read the
	 * bar's own pixels. Paint with the configured alpha and let the compositor
	 * blend against whatever is actually underneath. */
	rounded_rect(cr, MARGIN_SIDE, MARGIN_TOP,
	             b->width - 2 * MARGIN_SIDE, BAR_HEIGHT, PANEL_RADIUS);
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, RGB(0x17, 0x1b, 0x1c), b->panel_alpha);
	cairo_fill(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
}

void
draw_pill_r(Bar *b, int x, int y, int w, int h, double radius,
            double r, double g, double bl)
{
	rounded_rect(b->cr, x, y, w, h, radius);
	cairo_set_source_rgb(b->cr, r, g, bl);
	cairo_fill(b->cr);
}

void
draw_pill(Bar *b, int x, int y, int w, int h, double r, double g, double bl)
{
	draw_pill_r(b, x, y, w, h, PILL_RADIUS, r, g, bl);
}

static PangoLayout *
make_layout(Bar *b, const char *text, double size, int weight)
{
	PangoLayout *l = pango_cairo_create_layout(b->cr);
	PangoFontDescription *d = pango_font_description_new();

	pango_font_description_set_family(d, FONT_STACK);
	pango_font_description_set_absolute_size(d, size * PANGO_SCALE);
	pango_font_description_set_weight(d, weight);
	pango_layout_set_font_description(l, d);
	pango_layout_set_text(l, text, -1);
	pango_font_description_free(d);
	return l;
}

int
text_width(Bar *b, const char *text)
{
	PangoLayout *l = make_layout(b, text, FONT_SIZE, FONT_WEIGHT);
	int w, h;

	pango_layout_get_pixel_size(l, &w, &h);
	g_object_unref(l);
	return w;
}

int
text_width_sized(Bar *b, const char *text, double size, int weight)
{
	PangoLayout *l = make_layout(b, text, size, weight);
	int w, h;

	pango_layout_get_pixel_size(l, &w, &h);
	g_object_unref(l);
	return w;
}

/* Vertically centred text whose baseline keeps the glyph centred in the pill. */
/* Draw text vertically centred in a box of height `box_h` that starts at y.
 *
 * Centring against the constant BAR_HEIGHT only works for full-height pills.
 * A pill is 2*PILL_MARGIN shorter than the bar, so text centred on BAR_HEIGHT
 * sat several pixels above the pill's middle - visible in the sysinfo control,
 * whose memory figure is drawn inside a pill.
 */
void
draw_text_in(Bar *b, int x, int y, int box_h, const char *text,
             double size, int weight, double r, double g, double bl)
{
	PangoLayout *l = make_layout(b, text, size, weight);
	int tw, th;
	double ty;

	pango_layout_get_pixel_size(l, &tw, &th);
	ty = y + (box_h - th) / 2.0;

	cairo_set_source_rgb(b->cr, r, g, bl);
	cairo_move_to(b->cr, x, ty);
	pango_cairo_show_layout(b->cr, l);
	g_object_unref(l);
}

void
draw_text_n(Bar *b, int x, int y, const char *text, double size, int weight,
            double r, double g, double bl)
{
	draw_text_in(b, x, y, BAR_HEIGHT, text, size, weight, r, g, bl);
}

void
draw_text(Bar *b, int x, int y, const char *text, double r, double g, double bl)
{
	draw_text_n(b, x, y, text, FONT_SIZE, FONT_WEIGHT, r, g, bl);
}

/* Feedback overlay drawn over a pill or button.
 *
 * A translucent white veil reads the same on every colour (dark pill, green
 * launcher, purple bell), so no per-module colour maths is needed. */
void
draw_feedback(Bar *b, int x, int y, int w, int h, double radius, double alpha)
{
	if (alpha <= 0.0)
		return;

	/* Reset the operator: earlier module code leaves it in OVER, but a stray
	 * SOURCE would wipe the pill instead of tinting it. */
	cairo_set_operator(b->cr, CAIRO_OPERATOR_OVER);
	rounded_rect(b->cr, x, y, w, h, radius);
	/* OVERLAY is invisible on the fully saturated capsules (#00FF00 launcher),
	 * because overlay leaves pure hues unchanged. Draw the veil twice: an
	 * OVERLAY pass for hue-preserving lift, then a small ADD pass that visibly
	 * raises bright colours as well. */
	cairo_set_operator(b->cr, CAIRO_OPERATOR_OVERLAY);
	cairo_set_source_rgba(b->cr, 1, 1, 1, alpha);
	cairo_fill_preserve(b->cr);
	cairo_set_operator(b->cr, CAIRO_OPERATOR_ADD);
	cairo_set_source_rgba(b->cr, 1, 1, 1, alpha * 0.45);
	cairo_fill(b->cr);
	cairo_set_operator(b->cr, CAIRO_OPERATOR_OVER);
}

/* Wi-Fi symbol: a dot plus two arcs, each in its own colour.
 *
 * The three elements are spaced evenly so the symbol reads as three concentric
 * rings rather than two crowded arcs plus a stray dot. With one gap unit G:
 *
 *   dot centre      radius G        (drawn as a filled circle)
 *   middle arc      radius 2.5G
 *   outer arc       radius 4G
 *
 * The distance from the dot's edge to the middle arc, and from the middle arc
 * to the outer arc, is then 1.5G - G/2 and 4G - 2.5G = 1.5G: identical.
 */
void
draw_wifi(Bar *b, int x, int y, int w, int h, double r_top, double g_top,
          double bl_top, double r_mid, double g_mid, double bl_mid,
          double r_dot, double g_dot, double bl_dot)
{
	cairo_t *cr = b->cr;
	double cx = x + w / 2.0;
	/* Three concentric levels with equal spacing between them:
	 *   outer arc radius  R
	 *   middle arc radius R - P
	 *   dot radius        R - 2P
	 * so the gap between any two neighbours is the same P. Chosen so the outer
	 * arc fills the 18px box and the dot still reads as a dot (~4px across). */
	double R = w * 0.47;
	double P = (R - 1.9) / 2.0;
	double r_outer = R;
	double r_middle = R - P;
	double dot_r = R - 2.0 * P;
	/* Centre the whole symbol in the box. The drawing spans from
	 * base - r_outer (top of the outer arc) down to base + dot_r (bottom of the
	 * dot), so its midpoint sits at base + (dot_r - r_outer)/2. Solving for the
	 * box centre keeps the icon optically centred instead of hanging low. */
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
