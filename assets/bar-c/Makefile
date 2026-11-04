# Build the C bar. Deps: X11, cairo, pangocairo.
CC      ?= cc
PKGS     = x11 cairo pangocairo
CFLAGS  += -O2 -Wall -Wextra -Wno-unused-value -std=c11 -D_GNU_SOURCE \
           -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200809L \
           $(shell pkg-config --cflags $(PKGS))
LDLIBS  += $(shell pkg-config --libs $(PKGS)) -lm

SRC = src/bar.c src/modules.c src/draw.c src/util.c src/tooltip.c
BIN = i3-everforest-bar-c

all: $(BIN)

$(BIN): $(SRC) src/bar.h src/config.h
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)

clean:
	rm -f $(BIN) src/*.o

install: $(BIN)
	install -m 755 $(BIN) /usr/local/bin/$(BIN)

.PHONY: all clean install
