; =========================================================================
;  crt0.s -- C runtime for the Sprinter EvoSDK port (Фаза 1, SDCC 2.9.0)
; =========================================================================
;  Раскладка Scheme C (см. HW_NOTES.md §10.2):
;    0x0000-0x1FFF  SDK (WIN0/SRAM)        -- собирается отдельно
;    0x2000-0x23FF  стек 1 КБ (SP=0x23FF)
;    0x2400-0xFFFF  код+данные C (56320 Б = бюджет EvoSDK)
;
;  _entry линкуется ПЕРВЫМ в _CODE => лежит на code-loc (0x2400). Рантайм SDK
;  (в WIN0/SRAM на 0x0000) прыгает сюда после инициализации.
;
;  crt0.rel ДОЛЖЕН быть первым .rel в линкере, чтобы _entry попал в начало _CODE.
; =========================================================================

        .module crt0
        .globl  _main
        .globl  _evo_runtime_init
        .globl  _evo_runtime_shutdown
        .globl  l__INITIALIZER
        .globl  s__INITIALIZED
        .globl  s__INITIALIZER
        .globl  l__DATA
        .globl  s__DATA
        .globl  l__BSS
        .globl  s__BSS

        .area   _CODE
_entry::
        ; Entry from the PRELOAD loader (loader.asm): CACHE on (WIN0=SRAM = this
        ; code), A = the physical page the loader staged for WIN1. Map it, set
        ; the Scheme C stack, then run C. See HW_NOTES §9.2.
        out     (#0xA2), a            ; WIN1 = code chunk1 page
        ld      sp, #0x23FF
        call    gsinit
        call    _evo_runtime_init
        call    _main

        ; Exit code 0. _evo_runtime_shutdown copies a DRAM trampoline, turns
        ; CACHE off and does DSS.Exit -- it does not return.
        ld      l, #0
        call    _evo_runtime_shutdown
        di
        halt

        ; ----- порядок областей -----
        .area   _HOME
        .area   _INITIALIZER
        .area   _GSINIT
        .area   _GSFINAL
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSEG
        .area   _BSS
        .area   _HEAP

        ; ----- инициализация глобальных/статических -----
        .area   _GSINIT
gsinit::
        ; SDCC 2.9 кладёт неинициализированные глобалы в DATA. Сначала
        ; обнуляем DATA, затем сгенерированный GSINIT-код проставит значения.
        ld      hl, #s__DATA
        ld      bc, #l__DATA
        ld      a, b
        or      a, c
        jr      z, gsinit_copy_init
        ld      (hl), #0
        dec     bc
        ld      a, b
        or      a, c
        jr      z, gsinit_copy_init
        ld      d, h
        ld      e, l
        inc     de
        ldir

gsinit_copy_init:
        ; INITIALIZER -> INITIALIZED
        ld      bc, #l__INITIALIZER
        ld      a, b
        or      a, c
        jr      z, gsinit_clear_bss
        ld      de, #s__INITIALIZED
        ld      hl, #s__INITIALIZER
        ldir

gsinit_clear_bss:
        ; обнуление BSS
        ld      hl, #s__BSS
        ld      bc, #l__BSS
        ld      a, b
        or      a, c
        jr      z, gsinit_done
        ld      (hl), #0
        dec     bc
        ld      a, b
        or      a, c
        jr      z, gsinit_done
        ld      d, h
        ld      e, l
        inc     de
        ldir

gsinit_done:
        .area   _GSFINAL
        ret
