# Build less.exe (LESS.EXE) for 16-bit real-mode MS-DOS with the Free
# Pascal i8086-msdos cross-compiler.
#   make                                  fetch the pinned compiler into
#                                         build/fpc8086, then build
#   make FPC8086_ROOT=$HOME/opt/fpc/3.2.2 use an unpacked copy of the
#                                         same release instead
#
# The compiler's default configuration is ignored (-n) so that a host
# fpc.cfg cannot add units or targets; everything is given here.

FPC8086_ROOT ?= build/fpc8086
FPC_VERSION  := 3.2.2
MODEL        := compact

PPC      := $(FPC8086_ROOT)/bin/ppcross8086
RTLUNITS := $(FPC8086_ROOT)/lib/fpc/$(FPC_VERSION)/units/msdos/8086-$(MODEL)
OBJDIR   := build/obj

VERSION := $(shell cat VERSION)

FPCFLAGS = -n -Tmsdos -Cp8086 -Wm$(MODEL) -O2 -Xs -XX -CX \
           -vewn -Sew -Fu'$(RTLUNITS)/*' -Fi$(OBJDIR) -FU$(OBJDIR)

SOURCES := less16.pas

less.exe: $(SOURCES) $(OBJDIR)/version.inc $(PPC)
	$(PPC) $(FPCFLAGS) -o$@ less16.pas

# VERSION compiled in as a Pascal string constant.
$(OBJDIR)/version.inc: VERSION
	mkdir -p $(OBJDIR)
	printf "const Version = '%s';\n" "$(VERSION)" > $@

# The pinned compiler (scripts/fetch-fpc8086). An FPC8086_ROOT given on
# the command line must already be unpacked.
ifeq ($(FPC8086_ROOT),build/fpc8086)
$(PPC): build/fpc8086/.tar-sha256
build/fpc8086/.tar-sha256: scripts/fetch-fpc8086
	sh scripts/fetch-fpc8086 build/fpc8086
	touch $@
endif

test: less.exe
	sh tests/run.sh $(CURDIR)/less.exe

clean:
	rm -rf $(OBJDIR) less.exe *.o *.ppu *.map

.PHONY: test clean
