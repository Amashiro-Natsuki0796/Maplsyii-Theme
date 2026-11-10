/* Process spawning and click-region bookkeeping. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <stdint.h>
#include <errno.h>

#include "bar.h"

/* Run a shell command detached from the bar.
 *
 * Double-fork so it is reparented to init, setsid so it survives the bar, and
 * stdio to /dev/null so a chatty command cannot block on a full pipe. */
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
		if (fork() > 0)
			_exit(0);
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	waitpid(pid, NULL, 0);
}

void
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

static char *
dup_or_null(const char *s)
{
	return s ? strdup(s) : NULL;
}

void
add_region(Bar *b, int x, int y, int w, int h,
           const char *left, const char *middle, const char *right)
{
	HitRegion *r;

	if (b->region_count >= MAX_REGIONS)
		return;
	r = &b->regions[b->region_count++];
	r->x = x;
	r->y = y;
	r->w = w;
	r->h = h;
	r->left = dup_or_null(left);
	r->middle = dup_or_null(middle);
	r->right = dup_or_null(right);
	r->tip = NULL;
}

/* Attach the hover tooltip to the region just added. */
void
set_region_tip(Bar *b, const char *tip)
{
	if (b->region_count > 0)
		b->regions[b->region_count - 1].tip = tip ? strdup(tip) : NULL;
}

/* ---- i3 IPC ------------------------------------------------------------
 *
 * The bar used to run `i3-msg -t get_workspaces` through popen() on a timer:
 * a fork, an exec, a socket connect and a JSON dump every 60ms, forever. On
 * an idle desktop that was by far the bar's largest cost - it kept the X
 * server and the compositor busy repainting a window whose contents had not
 * changed.
 *
 * This talks the protocol directly instead. One connection is kept open, so
 * a refresh is a write plus a read on an existing socket: no fork, no exec,
 * no connection setup. i3 pushes an event on every change, so the timer can
 * be dropped entirely.
 *
 * Wire format: "i3-ipc" + u32 length + u32 type, then the body.
 */
#define I3_IPC_MAGIC "i3-ipc"
#define I3_IPC_GET_WORKSPACES 1
#define I3_IPC_SUBSCRIBE 2
#define I3_IPC_EVENT_WORKSPACE (1u << 31)
#define I3_IPC_EVENT_WINDOW    (1u << 31) | 3

static int i3_fd = -1;
static char *i3_socket_path;

static char *
i3_socket(void)
{
	if (i3_socket_path)
		return i3_socket_path;

	const char *env = getenv("I3SOCK");
	if (env && *env) {
		i3_socket_path = strdup(env);
		return i3_socket_path;
	}

	/* Fall back to the default location i3 advertises in its tree. */
	{
		const char *runtime = getenv("XDG_RUNTIME_DIR");
		const char *display = getenv("DISPLAY");
		char path[512];
		int n;

		if (runtime && display) {
			char *dot = strrchr(display, '.');
			const char *suffix = dot ? dot + 1 : "0";
			n = snprintf(path, sizeof path, "%s/i3/ipc-socket.%s",
			             runtime, suffix);
			if (n > 0 && n < (int)sizeof path &&
			    access(path, R_OK) == 0) {
				i3_socket_path = strdup(path);
				return i3_socket_path;
			}
		}
	}
	return NULL;
}

static int
i3_connect(void)
{
	if (i3_fd >= 0)
		return i3_fd;

	char *path = i3_socket();
	if (!path)
		return -1;

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;

	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	strncpy(addr.sun_path, path, sizeof addr.sun_path - 1);

	if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
		close(fd);
		return -1;
	}
	i3_fd = fd;
	return fd;
}

/* Send one message and read exactly one reply into a caller buffer.
 * Returns the number of body bytes, or -1 on any error. */
static int
i3_request(int type, const char *payload, char *out, size_t outsz)
{
	int fd = i3_connect();
	if (fd < 0)
		return -1;

	uint32_t len = payload ? (uint32_t)strlen(payload) : 0;
	char hdr[14];
	memcpy(hdr, I3_IPC_MAGIC, 6);
	memcpy(hdr + 6, &len, 4);
	memcpy(hdr + 10, &type, 4);

	if (write(fd, hdr, sizeof hdr) != (ssize_t)sizeof hdr)
		goto fail;
	if (len && write(fd, payload, len) != (ssize_t)len)
		goto fail;

	char rhdr[14];
	{
		size_t got = 0;
		while (got < sizeof rhdr) {
			ssize_t r = read(fd, rhdr + got, sizeof rhdr - got);
			if (r <= 0)
				goto fail;
			got += (size_t)r;
		}
	}
	if (memcmp(rhdr, I3_IPC_MAGIC, 6) != 0)
		goto fail;

	uint32_t rlen;
	memcpy(&rlen, rhdr + 6, 4);

	size_t take = rlen < outsz - 1 ? rlen : outsz - 1;
	size_t got = 0;
	while (got < take) {
		ssize_t r = read(fd, out + got, take - got);
		if (r <= 0)
			goto fail;
		got += (size_t)r;
	}
	/* Drain anything past the buffer so the stream stays in sync. */
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
	i3_fd = -1;
	return -1;
}

/* Ask i3 for the workspaces and copy the JSON into out.
 * Returns 0 on success. No fork, no exec. */
int
i3_get_workspaces(char *out, size_t outsz)
{
	return i3_request(I3_IPC_GET_WORKSPACES, NULL, out, outsz) < 0 ? -1 : 0;
}

/* Subscribe to workspace and window events. After this the same connection
 * delivers unsolicited event messages, so the bar can react instead of poll. */
int
i3_subscribe(void)
{
	char buf[512];
	return i3_request(I3_IPC_SUBSCRIBE,
	                  "[\"workspace\",\"window\"]", buf, sizeof buf) < 0
	           ? -1
	           : 0;
}

int
i3_fd_get(void)
{
	return i3_connect();
}

int
i3_pending(void)
{
	if (i3_fd < 0)
		return 0;
	struct pollfd p = { .fd = i3_fd, .events = POLLIN };
	return poll(&p, 1, 0) > 0 && (p.revents & POLLIN);
}

/* Read and discard one pending event message. */
void
i3_read_event(void)
{
	if (i3_fd < 0)
		return;

	char hdr[14];
	size_t got = 0;
	while (got < sizeof hdr) {
		ssize_t r = read(i3_fd, hdr + got, sizeof hdr - got);
		if (r <= 0) {
			close(i3_fd);
			i3_fd = -1;
			return;
		}
		got += (size_t)r;
	}
	uint32_t rlen;
	memcpy(&rlen, hdr + 6, 4);
	while (rlen > 0) {
		char scratch[512];
		size_t want = rlen < sizeof scratch ? rlen : sizeof scratch;
		ssize_t r = read(i3_fd, scratch, want);
		if (r <= 0) {
			close(i3_fd);
			i3_fd = -1;
			return;
		}
		rlen -= (uint32_t)r;
	}
}
