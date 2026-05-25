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
PACKSPK  ?= $(SDK_DIR)tools/pack_spk.py
DSS_EXE  ?= $(SDK_DIR)tools/dss_exe.py
MHMT     ?= $(SDK_DIR)tools/bin/mhmt
PACK_ASSETS ?= 0
RESOURCES_H ?= $(PROJECT)/resources.h
ASSETS_DAT ?= $(BUILD)/assets.dat
ASSETS_RAW ?= $(BUILD)/assets.raw.dat
EXE      ?= $(BUILD)/$(OUT).exe

# Scheme C
CODE_LOC ?= 0x2400

CPPFLAGS := $(SDCPPFLAGS) -I$(SDK_DIR) -I$(PROJECT) -I$(BUILD)

# crt0 должен идти первым в линковке (=> _entry на code-loc).
# SDCC 2.9.0 z80 runtime-хелперы (* / % , long, сдвиги): прямой sdldz80 НЕ
# подтягивает z80-lib SDCC, поэтому линкуем их явно (historical SDCC runtime).
SDCC290_RTL := compat div divsigned divulong mod modulong mul mullong shift
RTL_RELS := $(patsubst %,$(BUILD)/sdcc290_%.rel,$(SDCC290_RTL))
OBJS := $(BUILD)/crt0.rel $(BUILD)/lib_startup.rel $(BUILD)/main.rel $(RTL_RELS)

.PHONY: all clean resources assets exe
all: $(BUILD)/$(OUT).ihx $(ASSETS_DAT)

resources: $(RESOURCES_H)
assets: $(ASSETS_DAT)
exe: $(EXE)

$(RESOURCES_H): $(MANIFEST) $(RESGEN)
	$(PYTHON) $(RESGEN) $(MANIFEST) -o $@

ifeq ($(PACK_ASSETS),1)
$(ASSETS_RAW): $(MANIFEST) $(ASSETPACK) | $(BUILD)
	$(PYTHON) $(ASSETPACK) $(MANIFEST) -o $@

$(ASSETS_DAT): $(ASSETS_RAW) $(PACKSPK)
	$(PYTHON) $(PACKSPK) --mhmt $(MHMT) $< $@
else
$(ASSETS_DAT): $(MANIFEST) $(ASSETPACK) | $(BUILD)
	$(PYTHON) $(ASSETPACK) $(MANIFEST) -o $@
endif

# Direct DSS EXE requires CODE_LOC >= 0x4100. The current Scheme C default
# (0x2400) needs the Stage 2 loader, so this target is intentionally separate
# from `all` and dss_exe.py will reject the low-load case.
$(EXE): $(BUILD)/$(OUT).ihx $(ASSETS_DAT) $(DSS_EXE)
	$(PYTHON) $(DSS_EXE) $< $@ --load $(CODE_LOC) --entry $(CODE_LOC) --stack 0x23ff --assets $(ASSETS_DAT)

# --- Link: генерируем .lk и зовём sdldz80 напрямую ---
$(BUILD)/$(OUT).ihx: $(OBJS)
	@printf '%s\n' '-mjx'                  > $(BUILD)/$(OUT).lk
	@printf '%s\n' '-i $@'                >> $(BUILD)/$(OUT).lk
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

$(BUILD)/lib_startup.rel: $(SDK_DIR)lib_startup.asm | $(BUILD)
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
