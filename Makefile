# lightswitch — gestures from the MacBook ambient light sensor.
#
#   make            build build/lightswitch
#   make test       build and run the unit tests (no sensor required)
#   make demo       replay the committed fixtures through the detector
#   make traces     regenerate the fixtures in tests/traces
#   make ci         warnings-as-errors build plus tests
#   make install    install to $(PREFIX)/bin  (default /usr/local)

CC      ?= cc
CFLAGS  ?= -O2 -g
PREFIX  ?= /usr/local

BUILD   := build
WARN    := -Wall -Wextra -Wshadow -Wstrict-prototypes -Wmissing-prototypes
BASE    := -std=c11 -Iinclude $(WARN) $(CFLAGS)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  # Darwin's default namespace already exposes POSIX; forcing _POSIX_C_SOURCE
  # here would hide symbols the system frameworks need.
  ALL_CFLAGS := $(BASE) -DLS_HAVE_IOKIT=1
  PLATFORM_SRC := src/sensor_iokit.c
  FRAMEWORKS := -framework CoreFoundation -framework IOKit \
                -framework ApplicationServices
else
  ALL_CFLAGS := $(BASE) -DLS_HAVE_IOKIT=0 -D_POSIX_C_SOURCE=200809L
  PLATFORM_SRC :=
  FRAMEWORKS :=
endif

LDLIBS := -lm

CORE_SRC := src/detector.c src/config.c src/action.c src/trace.c \
            src/sensor.c src/sensor_replay.c src/ui.c
APP_SRC  := $(CORE_SRC) $(PLATFORM_SRC) src/main.c

CORE_OBJ := $(patsubst src/%.c,$(BUILD)/%.o,$(CORE_SRC))
APP_OBJ  := $(patsubst src/%.c,$(BUILD)/%.o,$(APP_SRC))

TEST_SRC := tests/test_detector.c tests/test_config.c tests/test_action.c \
            tests/test_trace.c tests/test_ui.c
TEST_BIN := $(patsubst tests/%.c,$(BUILD)/%,$(TEST_SRC))

TRACES := idle tap double_tap hold walk_past drift dark office_session
TRACE_FILES := $(patsubst %,tests/traces/%.lstrace,$(TRACES))

.PHONY: all test demo traces ci clean install uninstall help

all: $(BUILD)/lightswitch

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(ALL_CFLAGS) -c $< -o $@

$(BUILD)/lightswitch: $(APP_OBJ)
	$(CC) $(ALL_CFLAGS) $^ -o $@ $(FRAMEWORKS) $(LDLIBS)

$(BUILD)/lstrace-synth: tools/lstrace-synth.c | $(BUILD)
	$(CC) $(ALL_CFLAGS) $< -o $@ $(LDLIBS)

$(BUILD)/touchprobe: tools/touchprobe.c | $(BUILD)
ifeq ($(UNAME_S),Darwin)
	$(CC) $(ALL_CFLAGS) $< -o $@ -framework CoreFoundation -framework IOKit
else
	@echo "touchprobe is macOS-only; skipping"
endif

# Every test links the whole core; the objects are tiny and it keeps the
# dependency list from rotting as tests grow.
$(BUILD)/test_%: tests/test_%.c $(CORE_OBJ) tests/harness.h | $(BUILD)
	$(CC) $(ALL_CFLAGS) -Itests $< $(CORE_OBJ) -o $@ $(FRAMEWORKS) $(LDLIBS)

test: $(TEST_BIN)
	@echo
	@fail=0; for t in $(TEST_BIN); do ./$$t || fail=1; done; \
	 if [ $$fail -ne 0 ]; then echo "TESTS FAILED"; exit 1; fi; \
	 echo "all tests passed"

# Replay every fixture through the real binary — the fastest way to see what
# the detector does without owning the hardware.
demo: $(BUILD)/lightswitch
	@echo "Replaying recorded traces through the detector."
	@echo "Each fixture is a scenario; the lines under it are what was recognised."
	@echo
	@for f in $(TRACE_FILES); do \
	   printf '  %s\n' "$$(basename $$f .lstrace)"; \
	   out=$$($(BUILD)/lightswitch --no-config --replay $$f 2>&1 \
	          | grep -E '^\[|too low' || true); \
	   if [ -n "$$out" ]; then \
	     printf '%s\n' "$$out" | sed 's/^/      /'; \
	   else \
	     echo "      (nothing — correctly ignored)"; \
	   fi; \
	 done

traces: $(BUILD)/lstrace-synth
	@mkdir -p tests/traces
	@for s in $(TRACES); do \
	   $(BUILD)/lstrace-synth $$s > tests/traces/$$s.lstrace && \
	   echo "wrote tests/traces/$$s.lstrace"; \
	 done

ci:
	$(MAKE) clean
	$(MAKE) CFLAGS="-O2 -g -Werror" all test
	$(MAKE) CFLAGS="-O2 -g -Werror" $(BUILD)/lstrace-synth

install: $(BUILD)/lightswitch
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 $(BUILD)/lightswitch $(DESTDIR)$(PREFIX)/bin/lightswitch

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/lightswitch

clean:
	rm -rf $(BUILD)

help:
	@sed -n '2,9p' Makefile | sed 's/^# \{0,1\}//'
