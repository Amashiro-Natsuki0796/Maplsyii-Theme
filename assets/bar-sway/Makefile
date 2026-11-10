# Wayland Everforest bar.
#
# Pure wl_shm + cairo/pango: no GTK, no EGL. That is what keeps the binary and
# its dependency footprint close to the X11 bar's (~7 MB resident) instead of
# Waybar's ~29 MB.

CC      ?= cc
PKGS     = wayland-client cairo pangocairo xkbcommon
CFLAGS  += -O2 -Wall -Wextra -std=c11 -D_GNU_SOURCE -D_DEFAULT_SOURCE
CFLAGS  += $(shell pkg-config --cflags $(PKGS))
CFLAGS  += -Iproto
LDLIBS  += $(shell pkg-config --libs $(PKGS)) -lm

SRC  = src/bar.c src/wl.c src/draw.c src/modules.c src/util.c src/tooltip.c \
       proto/wlr-layer-shell-protocol.c \
       proto/xdg-shell-protocol.c
BIN  = i3-everforest-bar-wl

all: $(BIN)

$(BIN): $(SRC) $(wildcard src/*.h) $(wildcard proto/*.h)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)

clean:
	rm -f $(BIN)

.PHONY: all clean
