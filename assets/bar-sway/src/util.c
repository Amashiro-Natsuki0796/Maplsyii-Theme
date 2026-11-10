/* Process spawning, sway IPC, and click-region bookkeeping.
 *
 * The sway IPC section is ported from the X11 bar's i3 client: sway speaks the
 * same protocol, so only the socket discovery differs (SWAYSOCK instead of
 * I3SOCK). Keeping the connection open means a workspace refresh is a write and
 * a read, not a fork+exec of swaymsg 16 times a second.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "bar.h"

unsigned long
now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (unsigned long)ts.tv_sec * 1000UL + (unsigned long)(ts.tv_nsec / 1000000);
}

/* Spawn `cmd` detached and return the child's PID, or -1.
 *
 * Unlike spawn(), the child is not reaped: the caller keeps the PID so it can
 * tell whether the popup it opened is still running, and kill it later. The
 * child does setsid() so it becomes its own process-group leader, which makes
 * kill(-pid) take down wofi together with anything it started.
 */
pid_t
spawn_child(const char *cmd)
{
	pid_t pid;

	if (!cmd || !*cmd)
		return -1;

	pid = fork();
	if (pid < 0)
		return -1;
	if (pid == 0) {
		/* Detach completely.
		 *
		 * setsid() puts the child in its own session (so kill(-pid) reaches the
		 * whole menu), and the stdio redirection matters as much: without it
		 * the child inherits the bar's Wayland socket and its stdout, and a
		 * menu that writes or disconnects can take the bar down with it. */
		setsid();
		{
			int fd = open("/dev/null", O_RDWR);
			if (fd >= 0) {
				dup2(fd, STDIN_FILENO);
				dup2(fd, STDOUT_FILENO);
				dup2(fd, STDERR_FILENO);
				if (fd > STDERR_FILENO)
					close(fd);
			}
		}
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	return pid;
}

void
spawn(const char *cmd)
{
	pid_t pid;

	if (!cmd || !*cmd)
		return;

	pid = fork();
	if (pid < 0)
		return;
	if (pid == 0) {
		pid_t g = fork();
		if (g < 0)
			_exit(0);
		if (g > 0)
			_exit(0);
		setsid();
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	waitpid(pid, NULL, 0);
}

/* ---- click regions ---------------------------------------------------- */
void
add_region(Bar *b, int x, int y, int w, int h,
           const char *left, const char *middle, const char *right)
{
	HitRegion *r;

	if (b->region_count >= (int)(sizeof b->regions / sizeof b->regions[0]))
		return;

	r = &b->regions[b->region_count++];
	r->x = x;
	r->y = y;
	r->w = w;
	r->h = h;
	r->left = left ? strdup(left) : NULL;
	r->middle = middle ? strdup(middle) : NULL;
	r->right = right ? strdup(right) : NULL;
	r->tip = NULL;
}

void
set_region_tip(Bar *b, const char *tip)
{
	HitRegion *r;

	if (b->region_count <= 0)
		return;
	r = &b->regions[b->region_count - 1];
	free(r->tip);
	r->tip = tip ? strdup(tip) : NULL;
}

/* ---- sway IPC --------------------------------------------------------- */
#define IPC_MAGIC "i3-ipc"
#define IPC_GET_WORKSPACES   1
#define IPC_SUBSCRIBE        2
#define IPC_GET_TREE         4

static int ipc_fd = -1;
static char *ipc_path;

static char *
ipc_socket(void)
{
	if (ipc_path)
		return ipc_path;

	/* sway publishes SWAYSOCK; fall back to the same discovery i3 uses. */
	const char *env = getenv("SWAYSOCK");

	if (env && *env) {
		ipc_path = strdup(env);
		return ipc_path;
	}
	env = getenv("I3SOCK");
	if (env && *env) {
		ipc_path = strdup(env);
		return ipc_path;
	}

	const char *runtime = getenv("XDG_RUNTIME_DIR");
	const char *display = getenv("WAYLAND_DISPLAY");
	char path[512];
	int n;

	if (runtime && display) {
		/* sway names its socket sway-ipc.<uid>.<pid>.sock; find it with a
		 * fixed-size scan rather than shelling out to swaymsg. */
		char dir[512];
		n = snprintf(dir, sizeof dir, "%s", runtime);
		if (n > 0 && n < (int)sizeof dir) {
			/* Try the predictable name first (pid unknown, so glob by hand). */
			FILE *p;
			char cmd[600];

			snprintf(cmd, sizeof cmd, "ls -1 %s/sway-ipc.*.sock 2>/dev/null | head -1",
			         dir);
			p = popen(cmd, "r");
			if (p) {
				if (fgets(path, sizeof path, p)) {
					size_t len = strlen(path);
					while (len && (path[len - 1] == '\n' || path[len - 1] == ' '))
						path[--len] = '\0';
					if (len) {
						pclose(p);
						ipc_path = strdup(path);
						return ipc_path;
					}
				}
				pclose(p);
			}
		}
	}
	return NULL;
}

static int
ipc_connect(void)
{
	if (ipc_fd >= 0)
		return ipc_fd;

	char *path = ipc_socket();
	if (!path)
		return -1;

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;

	struct sockaddr_un addr;
	memset(&addr, 0, sizeof addr);
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, path, sizeof addr.sun_path - 1);

	if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
		close(fd);
		return -1;
	}
	ipc_fd = fd;
	return fd;
}

static int
ipc_request(int type, const char *payload, char *out, size_t outsz)
{
	int fd = ipc_connect();
	if (fd < 0)
		return -1;

	uint32_t len = payload ? (uint32_t)strlen(payload) : 0;
	char hdr[14];
	memcpy(hdr, IPC_MAGIC, 6);
	memcpy(hdr + 6, &len, 4);
	memcpy(hdr + 10, &type, 4);

	if (write(fd, hdr, sizeof hdr) != (ssize_t)sizeof hdr)
		goto fail;
	if (len && write(fd, payload, len) != (ssize_t)len)
		goto fail;

	char rhdr[14];
	size_t got = 0;
	while (got < sizeof rhdr) {
		ssize_t r = read(fd, rhdr + got, sizeof rhdr - got);
		if (r <= 0)
			goto fail;
		got += (size_t)r;
	}
	if (memcmp(rhdr, IPC_MAGIC, 6) != 0)
		goto fail;

	uint32_t rlen;
	memcpy(&rlen, rhdr + 6, 4);

	size_t take = rlen < outsz - 1 ? rlen : outsz - 1;
	got = 0;
	while (got < take) {
		ssize_t r = read(fd, out + got, take - got);
		if (r <= 0)
			goto fail;
		got += (size_t)r;
	}
	while (take < rlen) {
		char scratch[512];
		size_t want = rlen - take;
		if (want > sizeof scratch)
			want = sizeof scratch;
		ssize_t r = read(fd, scratch, want);
		if (r <= 0)
			goto fail;
		take += (size_t)r;
	}
	out[got] = '\0';
	return (int)got;

fail:
	close(fd);
	ipc_fd = -1;
	return -1;
}

int
sway_get_workspaces(char *out, size_t outsz)
{
	return ipc_request(IPC_GET_WORKSPACES, NULL, out, outsz) < 0 ? -1 : 0;
}

int
sway_subscribe(void)
{
	char buf[512];
	return ipc_request(IPC_SUBSCRIBE, "[\"workspace\",\"window\"]",
	                   buf, sizeof buf) < 0 ? -1 : 0;
}

int
sway_fd(void)
{
	return ipc_connect();
}

int
sway_pending(void)
{
	if (ipc_fd < 0)
		return 0;
	struct pollfd p = { .fd = ipc_fd, .events = POLLIN };
	return poll(&p, 1, 0) > 0 && (p.revents & POLLIN);
}

void
sway_read_event(void)
{
	if (ipc_fd < 0)
		return;

	char hdr[14];
	size_t got = 0;
	while (got < sizeof hdr) {
		ssize_t r = read(ipc_fd, hdr + got, sizeof hdr - got);
		if (r <= 0) {
			close(ipc_fd);
			ipc_fd = -1;
			return;
		}
		got += (size_t)r;
	}
	uint32_t rlen;
	memcpy(&rlen, hdr + 6, 4);
	while (rlen > 0) {
		char scratch[1024];
		size_t want = rlen < sizeof scratch ? rlen : sizeof scratch;
		ssize_t r = read(ipc_fd, scratch, want);
		if (r <= 0) {
			close(ipc_fd);
			ipc_fd = -1;
			return;
		}
		rlen -= (uint32_t)r;
	}
}

/* The focused window's title, taken from sway's tree.
 *
 * The X11 bar read _NET_ACTIVE_WINDOW/_NET_WM_NAME; under Wayland there is no
 * such property, so the tree is the only source. The reply is parsed with a
 * minimal scanner: find the object that has "focused": true and take its
 * "name". Good enough for a title, and it avoids a JSON dependency. */
/* Read a JSON string value that starts at `p` (which must point at the opening
 * quote) into buf, decoding the escapes sway actually emits.
 *
 * Only \" \\ \/ \n \t \r and \uXXXX are handled; that covers window titles in
 * practice, and anything else is copied through unchanged rather than dropped.
 */
static void
json_str(const char *p, char *buf, size_t bufsz)
{
	size_t i = 0;

	if (!bufsz)
		return;
	buf[0] = '\0';
	if (!p || *p != '"')
		return;
	p++;

	while (*p && *p != '"' && i + 1 < bufsz) {
		if (*p == '\\' && p[1]) {
			p++;
			switch (*p) {
			case 'n': buf[i++] = '\n'; break;
			case 't': buf[i++] = '\t'; break;
			case 'r': buf[i++] = '\r'; break;
			case 'b': buf[i++] = '\b'; break;
			case 'f': buf[i++] = '\f'; break;
			case 'u': {
				/* \uXXXX: titles legitimately contain these for symbols
				 * and CJK punctuation, so decode the BMP range. */
				unsigned cp = 0;
				int k, ok = 1;

				for (k = 1; k <= 4; k++) {
					char c = p[k];

					cp <<= 4;
					if (c >= '0' && c <= '9')      cp |= (unsigned)(c - '0');
					else if (c >= 'a' && c <= 'f') cp |= (unsigned)(c - 'a' + 10);
					else if (c >= 'A' && c <= 'F') cp |= (unsigned)(c - 'A' + 10);
					else { ok = 0; break; }
				}
				if (!ok)
					break;
				p += 4;
				/* Encode as UTF-8. */
				if (cp < 0x80) {
					buf[i++] = (char)cp;
				} else if (cp < 0x800) {
					if (i + 2 < bufsz) {
						buf[i++] = (char)(0xC0 | (cp >> 6));
						buf[i++] = (char)(0x80 | (cp & 0x3F));
					}
				} else {
					if (i + 3 < bufsz) {
						buf[i++] = (char)(0xE0 | (cp >> 12));
						buf[i++] = (char)(0x80 | ((cp >> 6) & 0x3F));
						buf[i++] = (char)(0x80 | (cp & 0x3F));
					}
				}
				break;
			}
			default: buf[i++] = *p; break;
			}
			p++;
		} else {
			buf[i++] = *p++;
		}
	}
	buf[i] = '\0';
}

/* Skip whitespace. */
static const char *
skip_ws(const char *p)
{
	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
		p++;
	return p;
}

/* Find the value for `key` inside the flat part of the object at `obj`.
 *
 * `obj` must point at the object's '{'. Only the object's own keys are
 * searched: nested arrays and objects are skipped by matching braces, so a
 * "name" belonging to a child node can never be mistaken for this one's.
 * That is the bug the previous version had - it searched backwards from
 * "focused" and picked up the workspace's name instead of the window's.
 */
/* Skip one JSON value starting at `p`; returns the position just past it.
 *
 * Nesting is handled by matching braces, and strings are skipped wholesale so
 * a brace inside a window title cannot throw off the depth count.
 */
static const char *
json_skip_value(const char *p)
{
	p = skip_ws(p);

	if (*p == '"') {
		p++;
		while (*p && *p != '"') {
			if (*p == '\\' && p[1])
				p++;
			p++;
		}
		return *p ? p + 1 : p;
	}

	if (*p == '{' || *p == '[') {
		char open = *p;
		char close = (open == '{') ? '}' : ']';
		int depth = 0;

		while (*p) {
			if (*p == '"') {
				p++;
				while (*p && *p != '"') {
					if (*p == '\\' && p[1])
						p++;
					p++;
				}
				if (*p)
					p++;
				continue;
			}
			if (*p == open) {
				depth++;
			} else if (*p == close) {
				depth--;
				if (!depth)
					return p + 1;
			}
			p++;
		}
		return p;
	}

	/* number, true, false, null */
	while (*p && *p != ',' && *p != '}' && *p != ']')
		p++;
	return p;
}

/* Find the value for `key` among the object's own fields.
 *
 * `obj` must point at the object's '{'. Nested objects and arrays are stepped
 * over with json_skip_value, so a key belonging to a child node is never
 * mistaken for this object's - the whole point of parsing the structure
 * instead of searching text.
 */
static const char *
json_field(const char *obj, const char *key)
{
	const char *p;

	if (!obj || *obj != '{')
		return NULL;

	p = skip_ws(obj + 1);

	while (*p && *p != '}') {
		char name[64];
		const char *keystart = p;
		const char *q;

		if (*p != '"')
			return NULL;

		/* Find the closing quote of the key. */
		q = p + 1;
		while (*q && *q != '"') {
			if (*q == '\\' && q[1])
				q++;
			q++;
		}
		if (!*q)
			return NULL;

		json_str(keystart, name, sizeof name);

		p = skip_ws(q + 1);
		if (*p != ':')
			return NULL;
		p = skip_ws(p + 1);

		if (strcmp(name, key) == 0)
			return p;

		p = json_skip_value(p);
		p = skip_ws(p);

		if (*p == ',') {
			p = skip_ws(p + 1);
			continue;
		}
		break;
	}
	return NULL;
}

/* Find the focused leaf node in sway's tree.
 *
 * The tree nests containers; the node that carries both "focused": true and a
 * non-null "app_id" is the client, and its "name" is the window title. Workspace
 * containers also report focused: true, which is why the search must key on
 * app_id rather than on focused alone.
 */
static const char *
find_focused_client(const char *buf_start, const char *p, const char **app_out)
{
	while ((p = strstr(p, "\"focused\"")) != NULL) {
		const char *v = strchr(p, ':');

		if (!v) { p++; continue; }
		v = skip_ws(v + 1);
		if (strncmp(v, "true", 4) != 0) { p++; continue; }

		/* Walk back to the '{' that opens this node: brace counting from the
		 * start would be exact but the tree is large, so instead look for the
		 * nearest preceding type/app_id marker and verify the object. */
		{
			const char *obj = p;
			const char *lo = p - 8192;

			/* Locate the object that opens this node by counting braces
			 * backwards from "focused". A node header is a few hundred bytes,
			 * so 8 KB is generous and still cheap. The lower bound must be
			 * clamped to the start of the buffer, or a focused node near the
			 * beginning would read before it. */
			if (lo < buf_start)
				lo = buf_start;
			{
				int depth = 0;
				const char *q = p;

				while (q > lo) {
					if (*q == '}') {
						depth++;
					} else if (*q == '{') {
						if (depth == 0) { obj = q; break; }
						depth--;
					}
					q--;
				}
			}

			{
				const char *app = json_field(obj, "app_id");
				const char *name;

				if (!app)
					return NULL;    /* not a client node */
				if (strncmp(app, "null", 4) == 0)
					return NULL;

				name = json_field(obj, "name");
				if (!name)
					return NULL;

				if (app_out)
					*app_out = app;
				return name;
			}
		}
	}
	return NULL;
}

int
sway_get_active_app(char *out, size_t outsz, char *cls, size_t clssz)
{
	static char buf[262144];
	int n = ipc_request(IPC_GET_TREE, NULL, buf, sizeof buf);
	const char *app = NULL;
	const char *name;

	if (out && outsz)
		out[0] = '\0';
	if (cls && clssz)
		cls[0] = '\0';
	if (n <= 0)
		return -1;

	name = find_focused_client(buf, buf, &app);
	if (!name)
		return -1;

	if (out && outsz)
		json_str(name, out, outsz);
	if (cls && clssz && app)
		json_str(app, cls, clssz);
	return 0;
}

