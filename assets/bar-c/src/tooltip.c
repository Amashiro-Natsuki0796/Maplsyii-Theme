/* Hover tooltip.
 *
 * The Python bar got tooltips from GTK. This is a raw X11 window: an
 * override-redirect, ARGB panel that pops under the hovered pill, sized to the
 * text, and is destroyed as soon as the pointer leaves the control.
 *
 * It is excluded from picom's blur, so it never picks up a frosted backdrop.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <cairo/cairo.h>
#include <cairo/cairo-xlib.h>
#include <pango/pangocairo.h>

#include <math.h>

#include "bar.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define TIP_PAD_X   10
#define TIP_PAD_Y   7
#define TIP_RADIUS  7.0
#define TIP_GAP     6      /* distance below the bar */
#define TIP_MAX_W   420

static Window tip_win;
static cairo_surface_t *tip_surf;
static cairo_t *tip_cr;

/* Destroy the current tooltip window, keeping the X connection alive. */
/* Tear the tooltip down.
 *
 * Order matters: the cairo objects hold an X Render Picture for tip_win, so
 * destroying the window first leaves cairo to free a dead Picture and X kills
 * the whole process with RenderBadPicture. Destroy cairo first, then the
 * window. */
void
tooltip_close(Bar *b)
{
	if (tip_cr) {
		cairo_destroy(tip_cr);
		tip_cr = NULL;
	}
	if (tip_surf) {
		cairo_surface_finish(tip_surf);
		cairo_surface_destroy(tip_surf);
		tip_surf = NULL;
	}
	if (tip_win) {
		XDestroyWindow(b->dpy, tip_win);
		XFlush(b->dpy);
		tip_win = 0;
	}
}

/* Show `text` centred under [x, x+w). Multiple lines are supported. */
void
tooltip_show(Bar *b, const char *text, int x, int w)
{
	PangoLayout *layout;
	PangoFontDescription *font;
	int tw = 0, th = 0;
	int box_w, box_h, box_x, box_y;
	int screen_w = b->width;
	int lines = 1;

	if (!text || !*text) {
			tooltip_close(b);
		return;
	}

	/* Measure. */
	layout = pango_cairo_create_layout(b->cr);
	font = pango_font_description_new();
	pango_font_description_set_family(font, "JetBrains Mono, sans-serif");
	pango_font_description_set_absolute_size(font, 12 * PANGO_SCALE);
	pango_layout_set_font_description(layout, font);
	pango_layout_set_width(layout, TIP_MAX_W * PANGO_SCALE);
	pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
	pango_layout_set_text(layout, text, -1);
	pango_layout_get_pixel_size(layout, &tw, &th);

	for (const char *p = text; *p; p++)
		if (*p == '\n')
			lines++;

	box_w = tw + 2 * TIP_PAD_X;
	box_h = th + 2 * TIP_PAD_Y;

	/* Centre under the pill, clamped to the screen. */
	box_x = x + w / 2 - box_w / 2;
	if (box_x < 4)
		box_x = 4;
	if (box_x + box_w > screen_w - 4)
		box_x = screen_w - 4 - box_w;
	box_y = WINDOW_HEIGHT + TIP_GAP;

	/* (Re)create the window. */
	tooltip_close(b);
	{
		XSetWindowAttributes attrs;

		attrs.override_redirect = True;
		attrs.background_pixel = 0;
		attrs.border_pixel = 0;
		attrs.colormap = b->cmap;
		attrs.event_mask = ExposureMask;

		tip_win = XCreateWindow(b->dpy, RootWindow(b->dpy, b->screen),
		                        box_x, box_y, box_w, box_h, 0, b->depth,
		                        InputOutput, b->visual,
		                        CWOverrideRedirect | CWBackPixel |
		                        CWBorderPixel | CWColormap | CWEventMask,
		                        &attrs);
	}
	XStoreName(b->dpy, tip_win, "i3-everforest-tooltip");
	{
		XClassHint *ch = XAllocClassHint();

		if (ch) {
			ch->res_name = (char *)"i3-everforest-tooltip";
			ch->res_class = (char *)"i3-everforest-tooltip";
			XSetClassHint(b->dpy, tip_win, ch);
			XFree(ch);
		}
	}
	XMapRaised(b->dpy, tip_win);

	tip_surf = cairo_xlib_surface_create(b->dpy, tip_win, b->visual,
	                                     box_w, box_h);
	tip_cr = cairo_create(tip_surf);

	/* Panel. */
	{
		double r = TIP_RADIUS;

		cairo_new_sub_path(tip_cr);
		cairo_arc(tip_cr, box_w - r, r, r, -M_PI / 2, 0);
		cairo_arc(tip_cr, box_w - r, box_h - r, r, 0, M_PI / 2);
		cairo_arc(tip_cr, r, box_h - r, r, M_PI / 2, M_PI);
		cairo_arc(tip_cr, r, r, r, M_PI, 3 * M_PI / 2);
		cairo_close_path(tip_cr);
		cairo_set_source_rgba(tip_cr, RGB(0x1b, 0x20, 0x21), 0.97);
		cairo_fill(tip_cr);

		cairo_set_source_rgba(tip_cr, RGB(0x4a, 0x52, 0x50), 0.9);
		cairo_set_line_width(tip_cr, 1.0);
		cairo_stroke(tip_cr);
	}

	/* Text. */
	cairo_move_to(tip_cr, TIP_PAD_X, TIP_PAD_Y);
	cairo_set_source_rgb(tip_cr, RGB(0xef, 0xeb, 0xd5));
	pango_cairo_show_layout(tip_cr, layout);

	cairo_surface_flush(tip_surf);
	XFlush(b->dpy);

	pango_font_description_free(font);
	g_object_unref(layout);
}
