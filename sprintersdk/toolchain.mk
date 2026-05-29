# toolchain.mk -- SDCC 2.9.0 toolchain selection for the Sprinter port (Фаза 1).
#
# Resolves SDCC 2.9.0 tools. Override the bin dir via env or config.local.mk:
#   SDCC290_BIN_DIR = /absolute/path/to/sdcc-2.9.0/bin
# Default below points at the binary found on this host (see HW_NOTES / memory).
# NB: the PATH `sdcc` is 4.5.0 here -- do NOT use it for Фаза 1 (CLAUDE.md §9).

-include $(SDK_DIR)config.local.mk

SDCC290_BIN_DIR ?= /Users/dmitry/dev/zx/sdcc2/opt/sdcc-2.9.0/bin

SDCC290_BIN_PATH := $(patsubst %/,%,$(abspath $(SDCC290_BIN_DIR)))
ifeq ($(wildcard $(SDCC290_BIN_PATH)/sdcc-2.9.0),)
ifneq ($(wildcard $(SDCC290_BIN_PATH)/opt/sdcc-2.9.0/bin/sdcc-2.9.0),)
SDCC290_BIN_PATH := $(SDCC290_BIN_PATH)/opt/sdcc-2.9.0/bin
endif
endif

ifeq ($(wildcard $(SDCC290_BIN_PATH)/sdcc-2.9.0),$(SDCC290_BIN_PATH)/sdcc-2.9.0)
SDCC    ?= $(SDCC290_BIN_PATH)/sdcc-2.9.0
else
SDCC    ?= sdcc
endif

ifeq ($(wildcard $(SDCC290_BIN_PATH)/sdcpp-2.9.0),$(SDCC290_BIN_PATH)/sdcpp-2.9.0)
SDCPP   ?= $(SDCC290_BIN_PATH)/sdcpp-2.9.0
else
SDCPP   ?= sdcpp
endif

ifeq ($(wildcard $(SDCC290_BIN_PATH)/as-z80-2.9.0),$(SDCC290_BIN_PATH)/as-z80-2.9.0)
SDASZ80 ?= $(SDCC290_BIN_PATH)/as-z80-2.9.0
else
SDASZ80 ?= sdasz80
endif

ifeq ($(wildcard $(SDCC290_BIN_PATH)/link-z80-2.9.0),$(SDCC290_BIN_PATH)/link-z80-2.9.0)
SDLDZ80 ?= $(SDCC290_BIN_PATH)/link-z80-2.9.0
else
SDLDZ80 ?= sdldz80
endif

PYTHON      ?= python3
SDCC_TARGET ?= -mz80
SDCC_OPT    ?= --opt-code-speed
SDCC_CFLAGS ?= $(SDCC_TARGET) $(SDCC_OPT)
SDCPPFLAGS  ?= -D__SPRINTER__       # таргет-макрос: Sprinter-специфика в общих исходниках (main.c/evo.h)
SDASZ_FLAGS ?= -plosgff       # as-z80: p=no-page l=lst o=obj s=sym g=undef-global f=relocs
