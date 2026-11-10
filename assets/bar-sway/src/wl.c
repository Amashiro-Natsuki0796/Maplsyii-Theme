/* Wayland plumbing: registry, shared-memory buffer, layer surface, input.
 *
 * The goal is the smallest correct native-Wayland path for a bar:
 *
 *   - wl_shm instead of EGL. The bar redraws a 1600x46 strip; a shared-memory
 *     buffer created once and painted with cairo costs nothing extra, and it
 *     keeps the binary free of an EGL/GL dependency (the X11 bar had none
 *     either, and the whole point of this rewrite is to stay light).
 *   - wlr-layer-shell for placement. It is what gives the compositor a
 *     reserved strip (like _NET_WM_STRUT on X11) and keeps the bar above normal
 *     windows without an override-redirect hack.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "bar.h"

static void
shm_format(void *data, struct wl_shm *shm, uint32_t format)
{
	(void)data; (void)shm; (void)format;
}

static const struct wl_shm_listener shm_listener = {
	.format = shm_format,
};

/* ---- layer surface callbacks ------------------------------------------ */
static void
ls_configure(void *data, struct zwlr_layer_surface_v1 *ls,
             uint32_t serial, uint32_t width, uint32_t height)
{
	struct wl_state *w = data;

	/* The compositor decides the width (the full output) and confirms the
	 * height we asked for. Re-create the buffer when either changes. */
	if (width > 0 && (int)width != w->width) {
		w->width = (int)width;
		if (w->buffer) {
			wl_buffer_destroy(w->buffer);
			w->buffer = NULL;
		}
	}
	if (height > 0)
		w->height = (int)height;

	zwlr_layer_surface_v1_ack_configure(ls, serial);
	w->configured = 1;

	if (!w->buffer && wl_create_buffer(w) != 0) {
		fprintf(stderr, "bar: cannot create buffer\n");
		return;
	}

	/* Attach the fresh buffer and commit an empty frame.
	 *
	 * Deliberately no painting here: the shm memory has just been mapped and
	 * cairo has not been bound to it yet (bar.c does that as soon as wl_init
	 * returns). Whoever owns the Bar calls bar_draw() and commits again with
	 * real content; committing now only satisfies the protocol requirement
	 * that a configured surface gets a buffer. */
	wl_surface_attach(w->surface, w->buffer, 0, 0);
	wl_surface_damage_buffer(w->surface, 0, 0, w->width, w->height);
	wl_surface_commit(w->surface);
	wl_display_flush(w->dpy);
}

static void
ls_closed(void *data, struct zwlr_layer_surface_v1 *ls)
{
	(void)ls;
	struct wl_state *w = data;
	/* The compositor closed us (output removed, or sway exiting). */
	w->configured = -1;
}

static const struct zwlr_layer_surface_v1_listener ls_listener = {
	.configure = ls_configure,
	.closed = ls_closed,
};

/* ---- registry --------------------------------------------------------- */
static void
reg_global(void *data, struct wl_registry *reg, uint32_t name,
           const char *iface, uint32_t version)
{
	struct wl_state *w = data;

	if (strcmp(iface, wl_compositor_interface.name) == 0) {
		w->compositor = wl_registry_bind(reg, name, &wl_compositor_interface,
		                                version < 4 ? version : 4);
	} else if (strcmp(iface, wl_shm_interface.name) == 0) {
		w->shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
		wl_shm_add_listener(w->shm, &shm_listener, w);
	} else if (strcmp(iface, wl_seat_interface.name) == 0) {
		w->seat = wl_registry_bind(reg, name, &wl_seat_interface,
		                          version < 5 ? version : 5);

		/* Attach the listener the moment the seat is bound.
		 *
		 * Binding it later (after wl_init returns) lost the very first
		 * capabilities event: libwayland reports it as "discarded" because no
		 * listener was registered when it arrived, so wl_seat_get_pointer()
		 * was never called and the bar ignored every click and hover. */
		extern void bar_seat_attach(struct wl_seat *seat);
		bar_seat_attach(w->seat);
	} else if (strcmp(iface, zwlr_layer_shell_v1_interface.name) == 0) {
		w->layer_shell = wl_registry_bind(reg, name,
		                                 &zwlr_layer_shell_v1_interface,
		                                 version < 4 ? version : 4);
	}
}

static void
reg_remove(void *data, struct wl_registry *reg, uint32_t name)
{
	(void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener reg_listener = {
	.global = reg_global,
	.global_remove = reg_remove,
};

/* ---- shared memory buffer --------------------------------------------- */
static int
create_shm_file(size_t size)
{
	char name[64];
	int fd;

	/* memfd_create would be shorter but needs _GNU_SOURCE; the XDG runtime
	 * dir trick is portable and leaves nothing behind. */
	snprintf(name, sizeof name, "%s/bar-wl-XXXXXX",
	         getenv("XDG_RUNTIME_DIR") ? getenv("XDG_RUNTIME_DIR") : "/tmp");
	fd = mkstemp(name);
	if (fd < 0)
		return -1;
	unlink(name);

	if (ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

int
wl_create_buffer(struct wl_state *w)
{
	int stride = w->width * 4;
	size_t size = (size_t)stride * (size_t)w->height;
	struct wl_shm_pool *pool;
	int fd;

	fd = create_shm_file(size);
	if (fd < 0) {
		fprintf(stderr, "bar: cannot create shm file: %s\n", strerror(errno));
		return -1;
	}

	w->shm_data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (w->shm_data == MAP_FAILED) {
		close(fd);
		w->shm_data = NULL;
		return -1;
	}
	w->shm_size = size;

	pool = wl_shm_create_pool(w->shm, fd, (int32_t)size);
	w->buffer = wl_shm_pool_create_buffer(pool, 0, w->width, w->height,
	                                     stride, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);

	return 0;
}

static void arm_frame(struct wl_state *w);

/* Commit the whole surface. */
void
wl_commit(struct wl_state *w)
{
	if (!w->surface || !w->buffer)
		return;

	wl_surface_attach(w->surface, w->buffer, 0, 0);
	wl_surface_damage_buffer(w->surface, 0, 0, w->width, w->height);
	wl_surface_commit(w->surface);

	/* Flush or the frame sits in the client-side buffer.
	 *
	 * The main loop polls the Wayland fd for readability and only dispatches
	 * when something arrives. Requests written by wl_surface_commit() are
	 * queued locally until a flush; without this the compositor never learned
	 * about the repaint, so the bar kept showing its first frame while the
	 * process itself looked healthy - which is exactly "the bar is frozen". */
	wl_display_flush(w->dpy);
}

/* Commit only a rectangle.
 *
 * The compositor still composites the whole surface (the buffer is the same
 * one), but it can skip re-uploading the untouched pixels and only repaint the
 * damaged region. The graph band is ~116x26 of a 1600x46 surface, so this is
 * the difference between touching 73k pixels per frame and touching 3k.
 */
void
wl_commit_rect(struct wl_state *w, int x, int y, int width, int height)
{
	if (!w->surface || !w->buffer)
		return;

	if (width <= 0 || height <= 0) {
		wl_commit(w);
		return;
	}

	/* Clamp the damage rectangle to the buffer.
	 *
	 * wl_surface.damage_buffer takes surface-local coordinates and is specified
	 * to accept a region at least partly inside the buffer, but passing a
	 * negative origin is not well defined: the protocol carries it as int, so
	 * an origin of -1 encodes fine yet describes a rectangle that starts
	 * outside the surface. Callers do compute x-1/y-1 to bleed over the
	 * antialiased edge of the previous frame, so the clamp belongs here rather
	 * than at every call site.
	 *
	 * This is also defensive: a mis-measured text width can push a plot
	 * rectangle past the right edge, and a compositor is free to reject or
	 * mis-handle a damage region that leaves the buffer. */
	{
		int bw = w->width > 0 ? w->width : 1;
		int bh = w->height > 0 ? w->height : 1;
		int x0 = x < 0 ? 0 : x;
		int y0 = y < 0 ? 0 : y;
		int x1 = x + width;
		int y1 = y + height;

		if (x1 > bw)
			x1 = bw;
		if (y1 > bh)
			y1 = bh;

		width = x1 - x0;
		height = y1 - y0;
		x = x0;
		y = y0;

		if (width <= 0 || height <= 0) {
			wl_commit(w);
			return;
		}
	}

	wl_surface_attach(w->surface, w->buffer, 0, 0);
	wl_surface_damage_buffer(w->surface, x, y, width, height);
	arm_frame(w);
	wl_surface_commit(w->surface);
	wl_display_flush(w->dpy);
}

/* Frame callback: the compositor tells us when the surface can take a new
 * frame. Submitting faster than the display refreshes is wasted work - the
 * previous frame is dropped by the compositor - while submitting slower makes
 * the graph visibly step. Following the callback is the only way to be at
 * exactly the display rate. */
static void
frame_done(void *data, struct wl_callback *cb, uint32_t time)
{
	struct wl_state *w = data;

	(void)time;
	wl_callback_destroy(cb);
	w->frame_cb = NULL;
	w->frame_ready = 1;
}

static const struct wl_callback_listener frame_listener = {
	.done = frame_done,
};

static void
arm_frame(struct wl_state *w)
{
	if (!w->surface || w->frame_cb)
		return;
	w->frame_ready = 0;
	w->frame_cb = wl_surface_frame(w->surface);
	wl_callback_add_listener(w->frame_cb, &frame_listener, w);
}

int
wl_frame_ready(struct wl_state *w)
{
	if (!w->frame_cb)
		return 1;      /* no callback armed: nothing is throttling us */
	return w->frame_ready;
}

/* ---- init ------------------------------------------------------------- */
int
wl_init(struct wl_state *w, int width, int height)
{
	memset(w, 0, sizeof *w);
	w->width = width;
	w->height = height;
	w->pointer_inside = 0;

	w->dpy = wl_display_connect(NULL);
	if (!w->dpy) {
		fprintf(stderr, "bar: cannot connect to Wayland display "
		                "(WAYLAND_DISPLAY=%s)\n",
		        getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "(unset)");
		return -1;
	}

	w->registry = wl_display_get_registry(w->dpy);
	wl_registry_add_listener(w->registry, &reg_listener, w);
	wl_display_roundtrip(w->dpy);

	if (!w->compositor || !w->shm || !w->layer_shell) {
		fprintf(stderr, "bar: missing globals (compositor=%p shm=%p "
		                "layer_shell=%p)\n",
		        (void *)w->compositor, (void *)w->shm, (void *)w->layer_shell);
		return -1;
	}

	w->surface = wl_compositor_create_surface(w->compositor);
	if (!w->surface)
		return -1;

	w->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
	    w->layer_shell, w->surface, NULL,
	    ZWLR_LAYER_SHELL_V1_LAYER_TOP, "i3-everforest-bar");

	zwlr_layer_surface_v1_add_listener(w->layer_surface, &ls_listener, w);

	/* Anchor to the top edge and span the full width, exactly like the X11
	 * bar's strut. exclusive_zone makes the compositor reserve the strip so
	 * tiled windows do not slide under it. */
	zwlr_layer_surface_v1_set_anchor(w->layer_surface,
	                                 ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
	                                 ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
	                                 ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_size(w->layer_surface, 0, (uint32_t)height);
	/* exclusive_zone reserves space so tiled windows do not slide under the
	 * bar. Set to the surface height; the compositor treats it as the strut. */
	zwlr_layer_surface_v1_set_exclusive_zone(w->layer_surface, height);
	zwlr_layer_surface_v1_set_keyboard_interactivity(
	    w->layer_surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);

	wl_surface_commit(w->surface);

	/* Wait for the first configure before anyone tries to draw. */
	while (w->configured == 0) {
		if (wl_display_dispatch(w->dpy) < 0) {
			fprintf(stderr, "bar: display dispatch failed during configure\n");
			return -1;
		}
	}
	if (w->configured < 0)
		return -1;

	return 0;
}

int
wl_dispatch(struct wl_state *w, int timeout_ms)
{
	(void)timeout_ms;
	/* wl_display_dispatch blocks. The main loop polls the fd itself so it can
	 * also watch the sway IPC socket, so this stays a thin wrapper. */
	return wl_display_dispatch(w->dpy);
}

void
wl_finish(struct wl_state *w)
{
	if (w->buffer) wl_buffer_destroy(w->buffer);
	if (w->layer_surface) zwlr_layer_surface_v1_destroy(w->layer_surface);
	if (w->surface) wl_surface_destroy(w->surface);
	if (w->pointer) wl_pointer_destroy(w->pointer);
	if (w->keyboard) wl_keyboard_destroy(w->keyboard);
	if (w->seat) wl_seat_destroy(w->seat);
	if (w->layer_shell) zwlr_layer_shell_v1_destroy(w->layer_shell);
	if (w->shm) wl_shm_destroy(w->shm);
	if (w->compositor) wl_compositor_destroy(w->compositor);
	if (w->registry) wl_registry_destroy(w->registry);
	if (w->shm_data) munmap(w->shm_data, w->shm_size);
	if (w->dpy) wl_display_disconnect(w->dpy);
}
