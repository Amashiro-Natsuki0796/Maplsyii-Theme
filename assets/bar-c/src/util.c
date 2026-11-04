/* Process spawning and click-region bookkeeping. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

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
