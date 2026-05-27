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

SDK_DIR ?= $(dir $(lastword $(MAKEFILE_LIST)))
include $(SDK_DIR)toolchain.mk

PROJECT  ?= .
OUT      ?= app
BUILD    ?= $(PROJECT)/_build
MANIFEST ?= $(PROJECT)/compile.bat
RESGEN   ?= $(SDK_DIR)tools/resgen.py
ASSETPACK ?= $(SDK_DIR)tools/assetpack.py
DSS_EXE  ?= $(SDK_DIR)tools/dss_exe.py
MHMT     ?= $(SDK_DIR)tools/bin/mhmt
PACK_ASSETS ?= 0
RESOURCES_H ?= $(PROJECT)/resources.h
ASSETS_DAT ?= $(BUILD)/assets.dat
EXE      ?= $(BUILD)/$(OUT).exe
IHX2BIN  ?= $(SDK_DIR)tools/ihx2bin.py
LOADER_SRC ?= $(SDK_DIR)loader.asm
LOADER_BIN ?= $(BUILD)/loader.bin
LOADER_ORG ?= 0x8100           # WIN2: canonical DSS program window (see loader.asm)

# Scheme C (mirror of EvoSDK): SDK code+data live in the SRAM region #0000-#1FFF
# (like EvoSDK #E000-#FFFF), the stack at #2000-#23FF, and C code+data is one
# contiguous block #2400-#FFFF (= the EvoSDK 56320 B budget).
# SDK code at #0100 (not #0000: sdld ignores -b base 0; #0000-#00FF is left for
# the RST/IM2 vectors, used in Phase 2). Still well inside the SRAM region.
SDK_LOC     ?= 0x0100           # SDK hot code (_SDK), in SRAM/WIN0
SDKDATA_LOC ?= 0x1600           # SDK mutable data (_SDKDATA), in SRAM
CODE_LOC    ?= 0x2400           # C code (crt0 first); C _DATA/_BSS follow contiguously

CPPFLAGS := $(SDCPPFLAGS) -I$(SDK_DIR) -I$(PROJECT) -I$(BUILD)

# crt0 должен идти первым в линковке (=> _entry на code-loc).
# SDCC 2.9.0 z80 runtime-хелперы (* / % , long, сдвиги): прямой sdldz80 НЕ
# подтягивает z80-lib SDCC, поэтому линкуем их явно (historical SDCC runtime).
SDCC290_RTL := compat div divsigned divulong mod modulong mul mullong shift
RTL_RELS := $(patsubst %,$(BUILD)/sdcc290_%.rel,$(SDCC290_RTL))
# SDK libraries by EvoSDK responsibility zone (mirror of evosdk/ file names).
SDK_LIB := lib_startup lib_tiles lib_sprites lib_input lib_sound
LIB_RELS := $(patsubst %,$(BUILD)/%.rel,$(SDK_LIB))
OBJS := $(BUILD)/crt0.rel $(LIB_RELS) $(BUILD)/main.rel $(RTL_RELS)

.PHONY: all clean resources assets exe
all: $(BUILD)/$(OUT).ihx $(ASSETS_DAT)

resources: $(RESOURCES_H)
assets: $(ASSETS_DAT)
exe: $(EXE)

$(RESOURCES_H): $(MANIFEST) $(RESGEN)
	$(PYTHON) $(RESGEN) $(MANIFEST) -o $@

$(ASSETS_DAT): $(MANIFEST) $(ASSETPACK) | $(BUILD)
	$(PYTHON) $(ASSETPACK) --paged $(MANIFEST) -o $@

ifeq ($(PACK_ASSETS),1)
DSS_PACK_ARGS := --pack --mhmt $(MHMT)
else
DSS_PACK_ARGS :=
endif

# --- PRELOAD loader binary (assembled standalone, linked at LOADER_ORG) ---
$(BUILD)/loader.rel: $(LOADER_SRC) | $(BUILD)
	$(SDASZ80) $(SDASZ_FLAGS) $@ $<
	cp $@ $(basename $@).o

$(LOADER_BIN): $(BUILD)/loader.rel
	@printf '%s\n' '-mjx' '-i $(BUILD)/loader.ihx' '-b _CODE = $(LOADER_ORG)' '$(BUILD)/loader.o' '-e' > $(BUILD)/loader.lk
	$(SDLDZ80) -n -f $(BUILD)/loader.lk
	$(PYTHON) $(IHX2BIN) $(BUILD)/loader.ihx $@

# Monoblock DSS PRELOAD EXE: header + loader + paged code/assets inside.
# DSS loads only the loader (#4100/WIN1); it stages code into pages, copies the
# hot chunk into SRAM (CACHE), and jumps to crt0 _entry (#2400). See HW_NOTES §9.2.
$(EXE): $(BUILD)/$(OUT).ihx $(ASSETS_DAT) $(DSS_EXE) $(LOADER_BIN)
	$(PYTHON) $(DSS_EXE) --monoblock --loader $(LOADER_BIN) $< $@ \
	    --load 0 --entry $(CODE_LOC) --stack 0x23ff --assets $(ASSETS_DAT) $(DSS_PACK_ARGS)

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

# --- asm (.s) -> .rel : crt0 + sdcc290_* runtime ---
# Этот sdld ищет объект как <base>.o (заменяет .rel->.o), поэтому делаем .o-копию
# (приём из evosdk_libs).
$(BUILD)/%.rel: $(SDK_DIR)%.s | $(BUILD)
	$(SDASZ80) $(SDASZ_FLAGS) $@ $<
	cp $@ $(basename $@).o

# --- asm (.asm) -> .rel : SDK libs lib_startup/tiles/sprites/input/sound ---
$(BUILD)/%.rel: $(SDK_DIR)%.asm | $(BUILD)
	$(SDASZ80) $(SDASZ_FLAGS) $@ $<
	cp $@ $(basename $@).o

# --- C (.c) -> .rel (в три шага, см. шапку) ---
$(BUILD)/main.rel: $(PROJECT)/main.c $(RESOURCES_H) | $(BUILD)
	$(SDCPP) $(CPPFLAGS) $< > $(BUILD)/main.i
	$(SDCC) $(SDCC_CFLAGS) --c1mode -o $(BUILD)/main.asm < $(BUILD)/main.i
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/main.asm
	cp $@ $(basename $@).o

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
