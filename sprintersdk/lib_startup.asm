; =========================================================================
;  lib_startup.asm -- Sprinter EvoSDK runtime core (EvoSDK responsibility zone)
; =========================================================================
;  Mirrors evosdk/lib_startup.asm: DSS bootstrap + video mode, palette,
;  swap_screen/clear_screen, vsync/time/delay, misc runtime (memset/memcpy/
;  rand16/border), and the shared VRAM/asset helpers used by lib_tiles.
;  Graphics/sprites/sound/input live in lib_tiles/lib_sprites/lib_sound/
;  lib_input (separate .rel, linked together).
; =========================================================================

        .module lib_startup

        .globl  _evo_runtime_init
        .globl  _evo_runtime_shutdown

        .globl  _memset
        .globl  _memcpy
        .globl  _rand16
        .globl  _border
        .globl  _vsync
        .globl  _swap_screen
        .globl  _time
        .globl  _delay
        .globl  _pal_clear
        .globl  _pal_bright
        .globl  _pal_select
        .globl  _pal_copy
        .globl  _pal_col
        .globl  _pal_custom
        .globl  _clear_screen

        ; --- shared helpers exported to lib_tiles.asm ---
        .globl  begin_vram_write
        .globl  end_vram_write
        .globl  _vram_base              ; back buffer base (#C000/#C140), set by begin_vram_write
        .globl  _sprites_render_before_swap
        .globl  _sprites_restore_after_swap
        .globl  _sync_tiles_to_shadow   ; from lib_tiles (dual-buffer tile sync)
        .globl  _tiles_clear_dirty      ; from lib_tiles

        .area   _SDK

; ---- SDK runtime region in SRAM (#0000-#1FFF, mirror of EvoSDK #E000-#FFFF).
;      Loader fills the tables into chunk0 before LDIR'ing it into SRAM. These
;      EQUs MUST match loader.asm and lib_tiles.asm. ----
EVO_PAGE_TABLE  = 0x1A00         ; asset phys page table (64 B), loader-filled
EVO_SAVED_VMODE = 0x1A40         ; original DSS video mode (for exit), loader-filled
EVO_META        = 0x1B00         ; EVP1 header+metadata copy, loader-filled

; The exit trampoline must execute with CACHE off (WIN0 = DSS BIOS, so SRAM is
; gone). We copy it -- and the values it needs -- transiently into WIN2 DRAM
; (the program is exiting, so clobbering C data there is harmless). No DRAM is
; reserved permanently.
EXIT_VMODE_DRAM = 0x8000
EXIT_CODE_DRAM  = 0x8001
EXIT_TRAMP_DRAM = 0x8010
EXIT_TRAMP_SP   = 0xBF00

_evo_runtime_init::
        ; Runs in SRAM (CACHE on). Video mode (#81 on both pages) was set by the
        ; PRELOAD loader before cache-on -- the SRAM runtime makes NO DSS calls.
        di
        ld      hl, #1
        ld      (_rand_seed1), hl
        ld      hl, #5
        ld      (_rand_seed2), hl
        ld      a, #3
        ld      (_pal_bright_level), a

        call    evo_meta_init          ; cache EVP1 table bases (loader filled #1A00+)

        xor     a
        out     (#0xC9), a             ; visible screen A, blank bit clear
        ld      (_screen_active), a
        call    clear_both_buffers_black
        call    _pal_clear
        ; NB: stay DI. With CACHE on, WIN0=SRAM, so the IM1 vector (#0038) and
        ; IM2 table are SRAM, not DSS -- an EI here would crash on the first
        ; frame IRQ. Phase 1 has no interrupt handler (vsync is polled). IM2 +
        ; EI come in Phase 2 (sound/time) once the handler lives in SRAM.
        ret

; void evo_runtime_shutdown(unsigned char exit_code)  [exit_code in L]
;   Copies a position-independent trampoline into a DRAM buffer (#B800, WIN2)
;   and jumps into it. The trampoline turns CACHE off (so RST #10 reaches the
;   real DSS BIOS at #0010), restores the video mode and WIN0 page saved by the
;   loader, then DSS.Exit. Does not return. (cf. evosdk_libs evo_exit.s.)
_evo_runtime_shutdown::
        di
        ; Launcher runs in SRAM (CACHE on): stash exit code + the saved video
        ; mode (read from SRAM) into WIN2 DRAM, copy the trampoline to WIN2, run.
        ld      a, l
        ld      (EXIT_CODE_DRAM), a
        ld      a, (EVO_SAVED_VMODE)
        ld      (EXIT_VMODE_DRAM), a
        ld      hl, #tramp_src
        ld      de, #EXIT_TRAMP_DRAM
        ld      bc, #tramp_end - tramp_src
        ldir
        jp      EXIT_TRAMP_DRAM

; Position-independent, straight-line trampoline body. Copied into WIN2 DRAM and
; run there so it survives CACHE off (which turns WIN0/SRAM into DSS BIOS). Only
; absolute addresses (ports + the transient values in WIN2), no internal jumps.
tramp_src:
        ld      sp, #EXIT_TRAMP_SP      ; DRAM stack (WIN0/SRAM gone after cache off)
        in      a, (#0x7B)              ; CACHE off -> WIN0 = DSS BIOS
        push    ix                      ; SetVMod clobbers IX
        ld      a, (EXIT_VMODE_DRAM)
        ld      b, #0
        ld      c, #0x50                ; DSS SetVMod (restore video mode)
        rst     #0x10
        pop     ix
        ld      a, #0xC0
        out     (#0x89), a              ; park PORT_Y
        ld      a, (EXIT_CODE_DRAM)
        ld      b, a
        ld      c, #0x41                ; DSS.Exit (does not return)
        rst     #0x10
tramp_end:

_memset::
        push    iy
        ld      iy, #4
        add     iy, sp
        ld      e, 0 (iy)               ; dst
        ld      d, 1 (iy)
        ld      c, 3 (iy)               ; len
        ld      b, 4 (iy)
        ld      a, b
        or      c
        jr      nz, 1$
        pop     iy
        ret
1$:
        ld      a, 2 (iy)               ; value
        pop     iy
        ld      l, e
        ld      h, d
        ld      (hl), a
        dec     bc
        ld      a, b
        or      c
        ret     z
        inc     de
        ldir
        ret

_memcpy::
        push    iy
        ld      iy, #4
        add     iy, sp
        ld      e, 0 (iy)               ; dst
        ld      d, 1 (iy)
        ld      l, 2 (iy)               ; src
        ld      h, 3 (iy)
        ld      c, 4 (iy)               ; len
        ld      b, 5 (iy)
        pop     iy
        ld      a, b
        or      c
        ret     z
        ldir
        ret

_rand16::
        ld      hl, (_rand_seed1)
        push    hl
        srl     h
        rr      l
        ex      de, hl
        ld      hl, (_rand_seed2)
        add     hl, de
        ld      (_rand_seed2), hl
        ld      a, l
        xor     #15
        ld      l, a
        ex      de, hl
        pop     hl
        sbc     hl, de
        ld      (_rand_seed1), hl
        ret

_border::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        and     #7
        out     (#0xCA), a              ; BORDER alias, see manual/include/ports.inc
        ret

_vsync::
        ; Real frame sync by polling #FFFE bit 5 (1 while Y>256 = bottom blank,
        ; 0 for Y<256). Wait for the high->low edge so callers resume at frame
        ; start. Sprinter only toggles this bit while CBL is active, so arm CBL
        ; in idle mode (#80 -> #004E) first. Pure polling -- DI-safe (Phase 1
        ; stays fully DI; no EI/HALT, see HW_NOTES §7.1). Ref:
        ; evosdk_libs/sprinter/lib/video_vsync.s, HW_NOTES §6.4.
        ld      bc, #0x004E             ; CBL_CTRL: idle-on keeps #FE.5 toggling
        ld      a, #0x80
        out     (c), a
        ld      de, #0x8000             ; timeout guard so we never hang
1$:                                     ; wait until bit5 = 1 (into blank)
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        jr      nz, 2$
        dec     de
        ld      a, d
        or      e
        jr      nz, 1$
        jp      inc_time_counter        ; timeout: tick and return, do not hang
2$:                                     ; wait until bit5 = 0 (frame start)
        ld      de, #0x8000
3$:
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        jp      z, inc_time_counter
        dec     de
        ld      a, d
        or      e
        jr      nz, 3$
        jp      inc_time_counter

_swap_screen::
        call    _sprites_render_before_swap
        call    _vsync
        in      a, (#0xC9)              ; flappybird model: read current RGMOD.0
        xor     #0x01
        and     #0x01
        out     (#0xC9), a
        ld      (_screen_active), a
        call    _sprites_restore_after_swap
        call    _sync_tiles_to_shadow   ; propagate partial tile updates to the
        ret                             ; new hidden buffer (keeps buffers in sync)

_time::
        ld      hl, #_time_counter + 3
        ld      d, (hl)
        dec     hl
        ld      e, (hl)
        dec     hl
        ld      a, (hl)
        dec     hl
        ld      l, (hl)
        ld      h, a
        ret

_delay::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      a, d
        or      e
        ret     z
1$:
        push    de
        call    _vsync
        pop     de
        dec     de
        ld      a, d
        or      e
        jr      nz, 1$
        ret

inc_time_counter:
        ld      hl, #_time_counter
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret

; Double buffer -- model used by flappybird grx_utils.asm and
; sdcc-sprinter-sdk/lib/gfx/gfx_lowlevel.s. DSS SetVMod #81 must be called
; for screen pages B=1 and B=0 by the loader. Runtime drawing maps a SINGLE
; VRAM page #50 into WIN3. For the selected PORT_Y(#89) scanline, CPU writes
; buffer 0 at #C000+x and buffer 1 at #C140+x (320 bytes apart). RGMOD(#C9).0
; selects the displayed buffer; back buffer = !visible.
VRAM_PAGE       = 0x50
VRAM_BUF0_BASE  = 0xC000
VRAM_BUF1_BASE  = 0xC140
VRAM_Y_OFFSET   = 28                    ; center 200-row Evo surface in 256 rows

clear_both_buffers_black:
        in      a, (#0xE2)
        ld      (_vram_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        ld      c, #0                   ; black
        ld      hl, #VRAM_BUF0_BASE
        call    fill_buffer_320x256
        ld      hl, #VRAM_BUF1_BASE
        call    fill_buffer_320x256
        jp      end_vram_write

_clear_screen::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; C = color (preserved across fills)
        call    begin_vram_write        ; WIN3 = #50
        ; Clear BOTH buffers so the background base stays in sync across flips
        ; (partial draw_tile updates are then synced per-cell by swap_screen).
        ld      hl, #VRAM_BUF0_BASE
        call    fill_buffer_320x256
        ld      hl, #VRAM_BUF1_BASE
        call    fill_buffer_320x256
        call    end_vram_write
        jp      _tiles_clear_dirty      ; background uniform -> drop dirty marks

; begin_vram_write: WIN3 = page #50; select the HIDDEN (back) buffer base.
; Returns #C000 when visible is buffer 1, #C140 when visible is buffer 0.
begin_vram_write::
        in      a, (#0xE2)
        ld      (_vram_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        in      a, (#0xC9)
        and     #1                      ; visible buffer (0/1)
        ld      hl, #VRAM_BUF1_BASE     ; visible 0 -> draw hidden buffer 1
        jr      z, 1$
        ld      hl, #VRAM_BUF0_BASE     ; visible 1 -> draw hidden buffer 0
1$:
        ld      (_vram_base), hl
        ret

end_vram_write::
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_vram_saved_win3)
        out     (#0xE2), a
        ret

fill_buffer_320x256:
        ; In: HL = row base (#C000/#C140, page #50 in WIN3), C = color.
        ; Fills all 256 scanlines. Sprinter row window is selected by PORT_Y;
        ; 320 pixels are two 160-byte accel fills (block-size latch is 8-bit).
        xor     a
1$:
        out     (#0x89), a
        push    af
        push    hl
        call    fill_row_320
        pop     hl
        pop     af
        inc     a
        jr      nz, 1$
        ret

fill_row_320:
        push    hl

        di
        ld      d, d                    ; accel: size mode
        ld      a, #160
        ld      c, c                    ; accel: horizontal fill mode
        ld      a, c
        ld      (hl), a                 ; accel fire: first 160 bytes
        ld      b, b                    ; accel off (stay DI: Phase 1 has no IRQ handler)

        ld      a, #160
        add     a, l
        ld      l, a
        jr      nc, 1$
        inc     h
1$:
        di
        ld      d, d
        ld      a, #160
        ld      c, c
        ld      a, c
        ld      (hl), a                 ; accel fire: second 160 bytes
        ld      b, b

        pop     hl
        ret

; -------------------------------------------------------------------------
;  Palette (EvoSDK lib_startup zone). Direct protocol from HW_NOTES.md §3:
;  WIN3=#50, PORT_Y=index. BIOS PIC_SET_PAL uses palette page A as an offset
;  inside the same VRAM page: page 0 at #C3E0..#C3E3, page 1 at #C3E4..#C3E7.
;  Direct writes therefore update both offsets, not VRAM page #55.
; -------------------------------------------------------------------------
_pal_clear::
        ld      hl, #_palette
        ld      b, #16
        xor     a
1$:
        ld      (hl), a
        inc     hl
        djnz    1$

        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    clear_pal_banks
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
        ret

clear_pal_banks:                        ; WIN3 = #50; zero both palette banks
        ld      b, #0
2$:
        ld      a, b
        out     (#0x89), a
        xor     a
        ld      (#0xC3E0), a
        ld      (#0xC3E1), a
        ld      (#0xC3E2), a
        ld      (#0xC3E3), a
        ld      (#0xC3E4), a
        ld      (#0xC3E5), a
        ld      (#0xC3E6), a
        ld      (#0xC3E7), a
        djnz    2$
        ret

_pal_bright::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        cp      #7
        jr      c, 1$
        ld      a, #6
1$:
        ld      (_pal_bright_level), a
        jp      apply_palette_all

_pal_col::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; id
        and     #15
        ld      c, a
        inc     hl
        ld      a, (hl)                 ; RGB222 color
        ld      b, #0
        ld      hl, #_palette
        add     hl, bc
        ld      (hl), a                 ; store color into _palette[id]
        jp      apply_palette_all       ; re-apply whole palette

_pal_custom::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ex      de, hl
        ld      de, #_palette
        ld      bc, #16
        ldir
        jp      apply_palette_all

_pal_copy::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; palette id
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = user RGB222[16] dest
        push    de
        call    map_palette_page        ; HL = payload in WIN1, WIN1 saved
        pop     de
        call    copy_palette_payload
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        ret

_pal_select::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; palette id
        call    map_palette_page        ; HL = payload in WIN1, WIN1 saved
        ld      de, #_palette
        call    copy_palette_payload
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        jp      apply_palette_all

copy_palette_payload:
        ; In: HL = EVOS PAL payload ([u16 count][count*(R,G,B)]),
        ;     DE = destination RGB222[16].
        inc     hl
        inc     hl
        ld      b, #16
1$:
        ld      a, (hl)                 ; R8
        inc     hl
        rlca
        rlca
        and     #3
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        ld      c, a

        ld      a, (hl)                 ; G8
        inc     hl
        rlca
        rlca
        and     #3
        add     a, a
        add     a, a
        or      c
        ld      c, a

        ld      a, (hl)                 ; B8
        inc     hl
        rlca
        rlca
        and     #3
        or      c
        ld      (de), a
        inc     de
        djnz    1$
        ret

; apply_palette_all: write _palette[16] to both screen palette banks.
apply_palette_all:
        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    apply_pal_banks
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
        ret

apply_pal_banks:                        ; WIN3 = #50
        ld      hl, #_palette
        ld      c, #0
3$:
        ld      a, (hl)
        push    hl
        call    write_palette_entry
        pop     hl
        inc     hl
        inc     c
        ld      a, c
        cp      #16
        jr      nz, 3$
        ret

write_palette_entry:
        ; C = palette index, A = RGB222. Hardware wants 6-bit channel values
        ; in bits 7..2, so pal_bright_table stores pre-shifted values.
        push    bc
        ld      e, a
        ld      a, c
        out     (#0x89), a

        ld      a, (_pal_bright_level)
        add     a, a
        add     a, a
        ld      l, a
        ld      h, #0
        ld      bc, #pal_bright_table
        add     hl, bc

        ld      a, e                    ; red = bits 4..5
        rrca
        rrca
        rrca
        rrca
        and     #3
        push    hl
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E0), a
        ld      (#0xC3E4), a
        pop     hl

        ld      a, e                    ; green = bits 2..3
        rrca
        rrca
        and     #3
        push    hl
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E1), a
        ld      (#0xC3E5), a
        pop     hl

        ld      a, e                    ; blue = bits 0..1
        and     #3
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E2), a
        ld      (#0xC3E6), a
        xor     a
        ld      (#0xC3E3), a
        ld      (#0xC3E7), a
        pop     bc
        ret

; -------------------------------------------------------------------------
;  EVP1 paged asset access (HW_NOTES §9.2, §15). The loader copied the EVP1
;  header+metadata to EVO_META (#1B00, SRAM). Tables are ID-indexed; access is
;  O(1): table_base + id*stride, then map one page into WIN1.
;
;  EVO_META layout: [16B EVP1 header][u8 img_count][img*4]
;                   [u8 pal_count][pal*3:{u8 page,u16 off}][...]
;  Fixed: img_count @ EVO_META+16, img table @ +17. pal table base depends on
;  img_count -> computed once by evo_meta_init.
; -------------------------------------------------------------------------
EVO_PAGE_TABLE  = 0x1A00                ; asset phys page table (loader-filled)
EVO_META_IMGCNT = 0x1B10                ; EVO_META + 16
EVO_IMG_TABLE   = 0x1B11                ; EVO_META + 17

evo_meta_init:
        ; _pal_base = EVO_IMG_TABLE + img_count*4 + 1 (skip pal_count byte)
        ld      a, (EVO_META_IMGCNT)
        ld      l, a
        ld      h, #0
        add     hl, hl
        add     hl, hl                  ; img_count*4
        ld      de, #EVO_IMG_TABLE
        add     hl, de                  ; -> pal_count byte
        inc     hl                      ; -> pal table
        ld      (_pal_base), hl
        ret

map_palette_page:
        ; In: A = palette id. Out: HL = payload in WIN1 (#4000+off); WIN1
        ; saved in _pal_saved_win1 (caller restores). record = _pal_base+id*3,
        ; record = { u8 logical_page, u16 offset }. The logical page must be
        ; resolved through page_table to a physical page (same as draw_tile).
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, l
        add     hl, hl                  ; id*2
        add     hl, de                  ; id*3
        ld      de, (_pal_base)
        add     hl, de                  ; -> record {u8 page, u16 off}
        ld      a, (hl)                 ; logical page
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = offset
        ; phys = page_table[logical]
        push    de                      ; save offset
        ld      e, a
        ld      d, #0
        ld      hl, #EVO_PAGE_TABLE
        add     hl, de
        ld      a, (hl)                 ; physical page
        pop     de                      ; restore offset
        ld      c, a
        in      a, (#0xA2)
        ld      (_pal_saved_win1), a    ; save WIN1
        ld      a, c
        out     (#0xA2), a              ; map physical palette page into WIN1
        ld      hl, #0x4000
        add     hl, de                  ; HL = payload
        ret

pal_bright_table:
        ; brightness 0..6, channel 0..3, values pre-shifted for RGB6<<2.
        .db     0,   0,   0,   0
        .db     0,   28,  56,  84
        .db     0,   56,  112, 168
        .db     0,   84,  168, 252
        .db     84,  140, 196, 252
        .db     168, 196, 224, 252
        .db     252, 252, 252, 252

        .area   _SDKDATA
        ; SDK mutable data, in the SRAM region (#1600). Saved video mode for the
        ; exit trampoline lives in SRAM #1A40 (loader-filled), read by the
        ; shutdown launcher before CACHE off.
_screen_active:
        .db     0
_time_counter:
        .db     0, 0, 0, 0
_rand_seed1:
        .dw     0
_rand_seed2:
        .dw     0
_palette:
        .db     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
_pal_bright_level:
        .db     0
_pal_saved_win3:
        .db     0
_vram_saved_win3:
        .db     0
_pal_saved_win1:
        .db     0
_pal_base:
        .dw     0
_vram_base:
        .dw     0
