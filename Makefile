CC       ?= cc
CFLAGS   ?= -O2 -Wall
# Portable across distros: let cups-config supply the right include/lib paths
# (Debian, Fedora/RHEL, Arch, openSUSE, Alpine all ship it with cups-devel).
CUPSCFG  := $(shell cups-config --cflags 2>/dev/null)
CUPSLIBS := $(shell cups-config --libs 2>/dev/null)
CFLAGS   += $(CUPSCFG)
# cups-config --libs gives -lcups; the raster API lives in -lcupsimage on CUPS 2.x.
LIBS     := $(if $(CUPSLIBS),$(CUPSLIBS),-lcups) -lcupsimage -lm

all: src/rastertotspl

src/rastertotspl: src/rastertotspl.c
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

tests/mkras: tests/mkras.c
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

test: src/rastertotspl tests/mkras
	sh tests/smoke.sh

clean:
	rm -f src/rastertotspl tests/mkras

.PHONY: all clean test
