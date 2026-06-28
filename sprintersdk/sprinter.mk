# sprinter.mk -- сборочные правила Sprinter-таргета (Фаза 1, скелет).
#
# Использование из каталога проекта:
#   make -f ../sprintersdk/sprinter.mk PROJECT=. OUT=empty
#
# Раскладка Scheme C: код+данные C линкуются с 0x2400 (SDK+стек -- 0x0000..0x23FF).
#
# ВАЖНО: SDCC 2.9.0-драйвер не умеет вызывать суффиксные as-z80-2.9.0/link-z80-2.9.0
# и не понимает расширение .s. Поэтому:
#   C:   sdcpp (препроцессор) -> sdcc --c1mode (.i -> .asm) -> as-z80 (.asm -> .rel)
#   asm: as-z80 напрямую (.s -> .rel)
#   link: sdldz80 -n -f <.lk> (генерируем линкер-скрипт)
# Рецепт сверен с рабочим build evosdk_libs (тот же SDCC 2.9.0).

# Capture immediately (:=) at parse time: later `include $(BUILD)/layout.mk` (the
# LAYOUT_PASS=2 raise) appends to MAKEFILE_LIST, so a lazy `?=` here would later
# resolve $(lastword ...) to layout.mk's dir (_build/) and break $(SDK_DIR)*.s rules.
ifndef SDK_DIR
SDK_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
endif
include $(SDK_DIR)toolchain.mk

PROJECT  ?= .
BUILD    ?= $(PROJECT)/_build
MANIFEST ?= $(PROJECT)/compile.bat
MANIFEST_OUTPUT := $(strip $(shell LC_ALL=C awk -F= 'tolower($$1) ~ /^[[:space:]]*set[[:space:]]+output[[:space:]]*$$/ {gsub(/\r/,"",$$2); print $$2; exit}' "$(MANIFEST)" 2>/dev/null))
OUT      ?= $(if $(MANIFEST_OUTPUT),$(basename $(notdir $(MANIFEST_OUTPUT))),app)
RESGEN   ?= $(SDK_DIR)tools/resgen.py
ASSETPACK ?= $(SDK_DIR)tools/assetpack.py
DSS_EXE  ?= $(SDK_DIR)tools/dss_exe.py
TRANSCODE_SOURCES ?= $(SDK_DIR)tools/transcode_sources.py
MHMT     ?= $(SDK_DIR)tools/bin/mhmt
SJASMPLUS ?= sjasmplus
PT3_PLAYER ?= $(SDK_DIR)pt3play.asm
AFX_PLAYER ?= $(SDK_DIR)ayfxplay.asm
PACK_ASSETS ?= 0
# UNROLL=1 builds the speed (unrolled) variants of the graphics output loops in
# lib_tiles/lib_sprites; UNROLL=0 (default) builds the compact looped variants.
# Passed to the assembler as a `UNROLL = N` prelude prepended to each SDK .asm
# (as-z80-2.9.0 has no -D; conditional assembly via `.if UNROLL`). See §8/CLAUDE.md.
UNROLL ?= 0
UNROLL_STAMP ?= $(BUILD)/unroll.stamp
# PAL256=1: 256-colour sprites (only index 255 transparent). Default 0 keeps the
# 16-colour rule (>=16 transparent). 256-colour palettes themselves are detected
# automatically by the SDK from the asset (no flag) -- this only affects sprite
# transparency packing. See §9.1.
PAL256 ?= 0
PAL256_STAMP ?= $(BUILD)/pal256.stamp
# NATIVE=1: native Sprinter screen -- full 320x256 surface (no centering) and
# per-pixel sprite X over the full width (0..319, 16-bit X). NATIVE=0 (default) is
# the EvoSDK-compatible 320x200 surface with 2px sprite X -- existing games unchanged.
# Prepended as `NATIVE = N` to each SDK .asm (conditional assembly via `.if NATIVE`).
# See plan.md §9.2 / CLAUDE.md §2 (deliberate coordinate deviation in native mode).
NATIVE ?= 0
NATIVE_STAMP ?= $(BUILD)/native.stamp
# SPRITE16=1 adds the opt-in immediate-mode 16x16 accel blit draw_sprite16()
# (masked, by pixel coords, no queue slot / no 64-sprite limit -- see HW_NOTES §13).
# Default 0: the code is not assembled, so existing builds are byte-identical and
# pay zero bytes. Prepended as `SPRITE16 = N` to each SDK .asm (`.if SPRITE16`) and
# passed to the C preprocessor (`-DSPRITE16`) to gate the evo.h declaration.
SPRITE16 ?= 0
SPRITE16_STAMP ?= $(BUILD)/sprite16.stamp
# SAMPLE_ASYNC=1 adds non-blocking sample playback (sample_play_async): the CBL
# FIFO is fed in the background from the #FF IM2 ISR while the game keeps running.
# It also NARROWS the accel DI windows in the sprite/clear/tile-restore hot loops
# (DI only around each accel op, EI between) so the refill IRQ is never starved.
# Default 0: none of it is assembled -> existing builds byte-identical, zero cost.
# Prepended as `SAMPLE_ASYNC = N` to each SDK .asm (`.if SAMPLE_ASYNC`) and passed
# to the C preprocessor (`-DSAMPLE_ASYNC`) to gate the evo.h declaration.
SAMPLE_ASYNC ?= 0
SAMPLE_ASYNC_STAMP ?= $(BUILD)/sample_async.stamp
# FILEIO=1 adds blocking DSS file I/O into paged memory (file_open/read/write/...,
# mem_alloc, page accessors). Calls run with CACHE off (WIN0=DSS BIOS) via a WIN2
# trampoline, IM1+EI for disk polling, interrupts/music frozen for the call. Needs
# the loader to hand off a trampoline page. Default 0 -> not assembled, byte-identical.
FILEIO ?= 0
FILEIO_STAMP ?= $(BUILD)/fileio.stamp
SEGA_EX ?= 0
SEGA_EX_STAMP ?= $(BUILD)/sega_ex.stamp
RESOURCES_H ?= $(PROJECT)/resources.h
ASSETS_DAT ?= $(BUILD)/assets.dat
CP866_SRC_DIR ?= $(BUILD)/src-cp866
CP866_STAMP ?= $(BUILD)/src-cp866.stamp
EXE      ?= $(BUILD)/$(OUT).exe
PROJECT_EXE ?= $(PROJECT)/$(OUT).exe
IHX2BIN  ?= $(SDK_DIR)tools/ihx2bin.py
LOADER_SRC ?= $(SDK_DIR)loader.asm
LOADER_BIN ?= $(BUILD)/loader.bin
LOADER_ORG ?= 0x8100           # WIN2: canonical DSS program window (see loader.asm)
PACK_STAMP ?= $(BUILD)/pack.stamp

# Scheme C (mirror of EvoSDK): SDK code+data live in the SRAM region #0000-#1FFF
# (like EvoSDK #E000-#FFFF), the stack at #2000-#23FF, and C code+data is one
# contiguous block #2400-#FFFF (= the EvoSDK 56320 B budget).
# SDK code at #0100 (not #0000: sdld ignores -b base 0; #0000-#00FF is left for
# the RST/IM2 vectors, used in Phase 2). Still well inside the SRAM region.
SDK_LOC     ?= 0x0100           # SDK hot code (_SDK), in SRAM/WIN0
# Auto-raising SRAM map. The downstream regions float above _SDK, never below
# these FLOORS (so every build that already fits keeps byte-identical addresses):
#   _SDKDATA  floor #1400   (SDK mutable data, after _SDK)
#   EVO_TABLES floor #1A00  (page table + saved slots + meta; size #600)
#   stack      #2000-#23FF  (1 KB, after the tables)
#   _CODE      #2400        (C image chunk0; rest of C spills to DRAM chunks)
# When build flags grow _SDK past a floor, layout.py (fed the pass-1 link map)
# computes the smallest raised layout and writes $(BUILD)/layout.mk; the EXE recipe
# re-runs the build with LAYOUT_PASS=2 to pick it up. See HW_NOTES / tools/layout.py.
LAYOUT      ?= $(SDK_DIR)tools/layout.py
EVO_TABLES  := 0x1A00           # page-table base (floor); evo_map.inc derives the rest
SDKDATA_LOC := 0x1400           # SDK mutable data (_SDKDATA), in SRAM (floor)
STACK_LOC   := 0x2000           # game stack base (floor)
STACK_TOP   := 0x23ff           # game stack top  (floor)  -> crt0 `ld sp,#STACK_TOP`
CODE_LOC    := 0x2400           # C code base (floor); crt0 first => _entry on CODE_LOC
ifeq ($(LAYOUT_PASS),2)
include $(BUILD)/layout.mk      # raised EVO_TABLES/SDKDATA_LOC/STACK_*/CODE_LOC
endif

CPPFLAGS := $(SDCPPFLAGS) -DNATIVE=$(NATIVE) -DSEGA_EX=$(SEGA_EX) -DSPRITE16=$(SPRITE16) -DSAMPLE_ASYNC=$(SAMPLE_ASYNC) -DFILEIO=$(FILEIO) -I$(SDK_DIR) -I$(PROJECT) -I$(BUILD)
CPPFLAGS_CP866 := $(SDCPPFLAGS) -DNATIVE=$(NATIVE) -DSEGA_EX=$(SEGA_EX) -DSPRITE16=$(SPRITE16) -DSAMPLE_ASYNC=$(SAMPLE_ASYNC) -DFILEIO=$(FILEIO) -I$(SDK_DIR) -I$(CP866_SRC_DIR) -I$(BUILD) -I$(PROJECT)
PROJECT_TEXT_SRCS := $(shell find $(PROJECT) -path $(BUILD) -prune -o -type f \( -name '*.c' -o -name '*.h' \) -print 2>/dev/null)

# crt0 должен идти первым в линковке (=> _entry на code-loc).
# SDCC 2.9.0 z80 runtime-хелперы (* / % , long, сдвиги): прямой sdldz80 НЕ
# подтягивает z80-lib SDCC, поэтому линкуем их явно (historical SDCC runtime).
SDCC290_RTL := compat div divsigned divulong mod modulong mul mullong shift rle
RTL_RELS := $(patsubst %,$(BUILD)/sdcc290_%.rel,$(SDCC290_RTL))
# SDK libraries by EvoSDK responsibility zone (mirror of evosdk/ file names).
SDK_LIB := lib_startup lib_tiles lib_sprites lib_input lib_sound lib_dss
LIB_RELS := $(patsubst %,$(BUILD)/%.rel,$(SDK_LIB))
OBJS := $(BUILD)/crt0.rel $(LIB_RELS) $(BUILD)/evo.rel $(BUILD)/main.rel $(RTL_RELS)
# Objects that embed the (raisable) map addresses -- crt0 (STACK_TOP), the SDK libs
# (EVO_* table symbols) and the loader (EVO_* / STAGE_*). On a LAYOUT_PASS=2 raise
# these are removed so the second pass rebuilds them unconditionally (the in-process
# regen would otherwise be flaky against second-granularity mtimes). evo/main/RTL
# objects carry no absolute map address (relocated at link), so they are kept.
LAYOUT_OBJS := $(BUILD)/crt0.rel $(LIB_RELS) $(BUILD)/loader.rel

.PHONY: all clean resources assets exe sprinter FORCE
all: $(BUILD)/$(OUT).ihx $(ASSETS_DAT)
sprinter: exe

resources: $(RESOURCES_H)
assets: $(ASSETS_DAT)
exe: $(PROJECT_EXE)

$(RESOURCES_H): $(MANIFEST) $(RESGEN)
	$(PYTHON) $(RESGEN) $(MANIFEST) -o $@

$(CP866_STAMP): $(PROJECT_TEXT_SRCS) $(RESOURCES_H) $(TRANSCODE_SOURCES) | $(BUILD)
	$(PYTHON) $(TRANSCODE_SOURCES) $(PROJECT) $(CP866_SRC_DIR) --encoding cp866
	@printf '%s\n' 'encoding=cp866' > $@

ifeq ($(PAL256),1)
PAL256_ARGS := --pal256
else
PAL256_ARGS :=
endif

$(ASSETS_DAT): $(MANIFEST) $(ASSETPACK) $(PT3_PLAYER) $(AFX_PLAYER) $(PAL256_STAMP) | $(BUILD)
	SJASMPLUS="$(SJASMPLUS)" PT3_PLAYER="$(PT3_PLAYER)" AFX_PLAYER="$(AFX_PLAYER)" $(PYTHON) $(ASSETPACK) --paged $(PAL256_ARGS) $(MANIFEST) -o $@

ifeq ($(PACK_ASSETS),1)
DSS_PACK_ARGS := --pack --mhmt $(MHMT)
else
DSS_PACK_ARGS :=
endif

FORCE:

$(PACK_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'PACK_ASSETS=$(PACK_ASSETS)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(UNROLL_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'UNROLL=$(UNROLL)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(PAL256_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'PAL256=$(PAL256)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(NATIVE_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'NATIVE=$(NATIVE)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(SPRITE16_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'SPRITE16=$(SPRITE16)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(SAMPLE_ASYNC_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'SAMPLE_ASYNC=$(SAMPLE_ASYNC)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(FILEIO_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'FILEIO=$(FILEIO)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

$(SEGA_EX_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'SEGA_EX=$(SEGA_EX)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

# Shared memory-map header: derives every loader/SDK table symbol from EVO_TABLES,
# so the whole map moves as one when the layout raises. Prepended to each SDK .asm
# and the loader. Regenerated only when EVO_TABLES changes (cmp) -> triggers the
# minimal re-assembly on the LAYOUT_PASS=2 raise.
EVO_MAP_INC := $(BUILD)/evo_map.inc
$(EVO_MAP_INC): FORCE | $(BUILD)
	@tmp="$@.tmp"; { \
	  printf 'EVO_TABLES = %s\n' '$(EVO_TABLES)'; \
	  printf 'EVO_PAGE_TABLE = EVO_TABLES\n'; \
	  printf 'EVO_SAVED_VMODE = EVO_TABLES + 0xC8\n'; \
	  printf 'EVO_SAVED_W0 = EVO_TABLES + 0xC9\n'; \
	  printf 'EVO_SAVED_W1 = EVO_TABLES + 0xCA\n'; \
	  printf 'EVO_SAVED_W3 = EVO_TABLES + 0xCB\n'; \
	  printf 'EVO_SAVED_MEM_CODE = EVO_TABLES + 0xCC\n'; \
	  printf 'EVO_SAVED_MEM_ASSETS = EVO_TABLES + 0xCD\n'; \
	  printf 'EVO_DSS_TRAMP = EVO_TABLES + 0xCE\n'; \
	  printf 'EVO_DSS_TRAMP_OFF = EVO_TABLES + 0xCF\n'; \
	  printf 'EVO_META = EVO_TABLES + 0x100\n'; \
	  printf 'EVP_GFX_PAGES = EVO_TABLES + 0x105\n'; \
	  printf 'EVO_META_IMGCNT = EVO_TABLES + 0x110\n'; \
	  printf 'EVO_IMG_TABLE = EVO_TABLES + 0x111\n'; \
	} > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

STACK_STAMP := $(BUILD)/stack.stamp
$(STACK_STAMP): FORCE | $(BUILD)
	@tmp="$@.tmp"; \
	printf '%s\n' 'STACK_TOP=$(STACK_TOP)' > "$$tmp"; \
	if test -f "$@" && cmp -s "$$tmp" "$@"; then rm -f "$$tmp"; else mv "$$tmp" "$@"; fi

# --- PRELOAD loader binary (assembled standalone, linked at LOADER_ORG) ---
# Prepend the shared map header (EVO_* table addresses, so the loader writes the
# tables at the same -- possibly raised -- addresses the SDK reads them) and
# `FILEIO = N` (loader hands off its page + trampoline body only under FILEIO=1).
$(BUILD)/loader.rel: $(LOADER_SRC) $(FILEIO_STAMP) $(EVO_MAP_INC) | $(BUILD)
	@cat $(EVO_MAP_INC) > $(BUILD)/loader.gen.asm
	@printf 'FILEIO = %s\n' '$(FILEIO)' >> $(BUILD)/loader.gen.asm
	@cat $< >> $(BUILD)/loader.gen.asm
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/loader.gen.asm
	cp $@ $(basename $@).o

$(LOADER_BIN): $(BUILD)/loader.rel
	@printf '%s\n' '-mjx' '-i $(BUILD)/loader.ihx' '-b _CODE = $(LOADER_ORG)' '$(BUILD)/loader.o' '-e' > $(BUILD)/loader.lk
	$(SDLDZ80) -n -f $(BUILD)/loader.lk
	$(PYTHON) $(IHX2BIN) $(BUILD)/loader.ihx $@

# Monoblock DSS PRELOAD EXE: header + loader + paged code/assets inside.
# DSS loads only the loader (#4100/WIN1); it stages code into pages, copies the
# hot chunk into SRAM (CACHE), and jumps to crt0 _entry (#2400). See HW_NOTES §9.2.
$(EXE): $(BUILD)/$(OUT).ihx $(ASSETS_DAT) $(DSS_EXE) $(LOADER_BIN) $(PACK_STAMP) $(MANIFEST) $(LAYOUT)
ifeq ($(LAYOUT_PASS),2)
	$(PYTHON) $(DSS_EXE) --monoblock --loader $(LOADER_BIN) $< $@ \
	    --load 0 --entry $(CODE_LOC) --stack $(STACK_TOP) --tables $(EVO_TABLES) --assets $(ASSETS_DAT) \
	    --manifest $(MANIFEST) --map $(BUILD)/$(OUT).map $(DSS_PACK_ARGS)
else
	@$(PYTHON) $(LAYOUT) --map $(BUILD)/$(OUT).map --out $(BUILD)/layout.mk
	@if test -s $(BUILD)/layout.mk; then \
	    echo ">> SDK overflows the floor SRAM map -- raising layout (LAYOUT_PASS=2)"; \
	    rm -f $(LAYOUT_OBJS) $(LAYOUT_OBJS:.rel=.o) $(BUILD)/loader.bin \
	          $(BUILD)/$(OUT).ihx $(BUILD)/$(OUT).map; \
	    $(MAKE) LAYOUT_PASS=2 $@; \
	else \
	    $(PYTHON) $(DSS_EXE) --monoblock --loader $(LOADER_BIN) $< $@ \
	        --load 0 --entry $(CODE_LOC) --stack $(STACK_TOP) --tables $(EVO_TABLES) --assets $(ASSETS_DAT) \
	        --manifest $(MANIFEST) --map $(BUILD)/$(OUT).map $(DSS_PACK_ARGS); \
	fi
endif

$(PROJECT_EXE): $(EXE)
	cp $< $@

# --- Link: генерируем .lk и зовём sdldz80 напрямую ---
$(BUILD)/$(OUT).ihx: $(OBJS)
	@printf '%s\n' '-mjx'                  > $(BUILD)/$(OUT).lk
	@printf '%s\n' '-i $@'                >> $(BUILD)/$(OUT).lk
	@printf '%s\n' '-b _SDK = $(SDK_LOC)' >> $(BUILD)/$(OUT).lk
	@printf '%s\n' '-b _SDKDATA = $(SDKDATA_LOC)' >> $(BUILD)/$(OUT).lk
	@printf '%s\n' '-b _CODE = $(CODE_LOC)' >> $(BUILD)/$(OUT).lk
	@for rel in $(OBJS); do printf '%s\n' "$$rel" >> $(BUILD)/$(OUT).lk; done
	@printf '%s\n' '-e'                   >> $(BUILD)/$(OUT).lk
	$(SDLDZ80) -n -f $(BUILD)/$(OUT).lk

# crt0 carries the game stack pointer (`ld sp,#STACK_TOP`), which the layout raises
# together with the table region -- prepend STACK_TOP (floor #23ff). Explicit rule
# overrides the generic .s rule below.
$(BUILD)/crt0.rel: $(SDK_DIR)crt0.s $(STACK_STAMP) | $(BUILD)
	@printf 'STACK_TOP = %s\n' '$(STACK_TOP)' > $(BUILD)/crt0.gen.s
	@cat $< >> $(BUILD)/crt0.gen.s
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/crt0.gen.s
	cp $@ $(basename $@).o

# --- asm (.s) -> .rel : sdcc290_* runtime ---
# Этот sdld ищет объект как <base>.o (заменяет .rel->.o), поэтому делаем .o-копию
# (приём из evosdk_libs).
$(BUILD)/%.rel: $(SDK_DIR)%.s | $(BUILD)
	$(SDASZ80) $(SDASZ_FLAGS) $@ $<
	cp $@ $(basename $@).o

# --- asm (.asm) -> .rel : SDK libs lib_startup/tiles/sprites/input/sound ---
# Prepend `UNROLL = N` and `NATIVE = N` so the libs can select compile-time variants
# via `.if UNROLL` / `.if NATIVE` (as-z80 has no -D). Changing either re-touches its stamp.
$(BUILD)/%.rel: $(SDK_DIR)%.asm $(UNROLL_STAMP) $(NATIVE_STAMP) $(SEGA_EX_STAMP) $(SPRITE16_STAMP) $(SAMPLE_ASYNC_STAMP) $(FILEIO_STAMP) $(EVO_MAP_INC) | $(BUILD)
	@cat $(EVO_MAP_INC) > $(BUILD)/$*.gen.asm
	@printf 'UNROLL = %s\nNATIVE = %s\nSEGA_EX = %s\nSPRITE16 = %s\nSAMPLE_ASYNC = %s\nFILEIO = %s\n' '$(UNROLL)' '$(NATIVE)' '$(SEGA_EX)' '$(SPRITE16)' '$(SAMPLE_ASYNC)' '$(FILEIO)' >> $(BUILD)/$*.gen.asm
	@cat $< >> $(BUILD)/$*.gen.asm
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/$*.gen.asm
	cp $@ $(basename $@).o

# --- C (.c) -> .rel (в три шага, см. шапку) ---
$(BUILD)/evo.rel: $(SDK_DIR)evo.c $(SDK_DIR)evo.h $(NATIVE_STAMP) $(SEGA_EX_STAMP) | $(BUILD)
	$(SDCPP) $(CPPFLAGS) $< > $(BUILD)/evo.i
	$(SDCC) $(SDCC_CFLAGS) --c1mode -o $(BUILD)/evo.asm < $(BUILD)/evo.i
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/evo.asm
	cp $@ $(basename $@).o

$(BUILD)/main.rel: $(CP866_STAMP) $(NATIVE_STAMP) $(SEGA_EX_STAMP) | $(BUILD)
	$(SDCPP) $(CPPFLAGS_CP866) $(CP866_SRC_DIR)/main.c > $(BUILD)/main.i
	$(SDCC) $(SDCC_CFLAGS) --c1mode -o $(BUILD)/main.asm < $(BUILD)/main.i
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/main.asm
	cp $@ $(basename $@).o

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
