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

# Scheme C
CODE_LOC ?= 0x2400

CPPFLAGS := $(SDCPPFLAGS) -I$(SDK_DIR) -I$(PROJECT) -I$(BUILD)

# crt0 должен идти первым в линковке (=> _entry на code-loc)
OBJS := $(BUILD)/crt0.rel $(BUILD)/main.rel

.PHONY: all clean
all: $(BUILD)/$(OUT).ihx

# --- Link: генерируем .lk и зовём sdldz80 напрямую ---
$(BUILD)/$(OUT).ihx: $(OBJS)
	@printf '%s\n' '-mjx'                  > $(BUILD)/$(OUT).lk
	@printf '%s\n' '-i $@'                >> $(BUILD)/$(OUT).lk
	@printf '%s\n' '-b _CODE = $(CODE_LOC)' >> $(BUILD)/$(OUT).lk
	@for rel in $(OBJS); do printf '%s\n' "$$rel" >> $(BUILD)/$(OUT).lk; done
	@printf '%s\n' '-e'                   >> $(BUILD)/$(OUT).lk
	$(SDLDZ80) -n -f $(BUILD)/$(OUT).lk

# --- asm (.s) -> .rel ---
# Этот sdld ищет объект как <base>.o (заменяет .rel->.o), поэтому делаем .o-копию
# (приём из evosdk_libs).
$(BUILD)/crt0.rel: $(SDK_DIR)crt0.s | $(BUILD)
	$(SDASZ80) $(SDASZ_FLAGS) $@ $<
	cp $@ $(basename $@).o

# --- C (.c) -> .rel (в три шага, см. шапку) ---
$(BUILD)/main.rel: $(PROJECT)/main.c | $(BUILD)
	$(SDCPP) $(CPPFLAGS) $< > $(BUILD)/main.i
	$(SDCC) $(SDCC_CFLAGS) --c1mode -o $(BUILD)/main.asm < $(BUILD)/main.i
	$(SDASZ80) $(SDASZ_FLAGS) $@ $(BUILD)/main.asm
	cp $@ $(basename $@).o

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
