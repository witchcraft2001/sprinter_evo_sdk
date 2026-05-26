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
        .globl  _evos_assets_ptr
        .globl  _evos_assets_len

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
        .globl  find_asset_record
        .globl  _asset_found_record

        .area   _CODE

; ---- runtime table region in the WIN2 data page (#B000-#BFFF), filled by
;      loader.asm. DRAM, cache-independent, not remapped during draws. These
;      EQUs MUST match loader.asm. ----
EVO_SAVED_SLOT0 = 0xB400
EVO_SAVED_VMODE = 0xB401
EVO_EXIT_CODE   = 0xB402
EVO_TRAMP_BUF   = 0xB800         ; DRAM buffer for the cache-off exit trampoline
EVO_TRAMP_SP    = 0xBF00         ; DRAM stack for the cache-off DSS RST calls

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

        xor     a
        out     (#0xC9), a             ; visible screen A, blank bit clear
        ld      (_screen_active), a
        call    clear_both_buffers_black
        call    _pal_clear
        ei
        ret

; void evo_runtime_shutdown(unsigned char exit_code)  [exit_code in L]
;   Copies a position-independent trampoline into a DRAM buffer (#B800, WIN2)
;   and jumps into it. The trampoline turns CACHE off (so RST #10 reaches the
;   real DSS BIOS at #0010), restores the video mode and WIN0 page saved by the
;   loader, then DSS.Exit. Does not return. (cf. evosdk_libs evo_exit.s.)
_evo_runtime_shutdown::
        di
        ld      a, l
        ld      (EVO_EXIT_CODE), a
        ld      hl, #tramp_src
        ld      de, #EVO_TRAMP_BUF
        ld      bc, #tramp_end - tramp_src
        ldir
        jp      EVO_TRAMP_BUF

; Position-independent, straight-line trampoline body. Copied to #B800 (WIN2
; DRAM) and run there so it survives CACHE off (which turns WIN0/SRAM into BIOS).
; Uses only absolute addresses (ports + saved-state in WIN2), no internal jumps.
tramp_src:
        ld      sp, #EVO_TRAMP_SP       ; DRAM stack (WIN0 is gone after cache off)
        in      a, (#0x7B)              ; CACHE off -> WIN0 = DSS BIOS
        ld      bc, #0x0089             ; silence CBL DAC
        xor     a
        out     (c), a
        push    ix                      ; SetVMod clobbers IX
        ld      a, (EVO_SAVED_VMODE)
        ld      b, #0
        ld      c, #0x50                ; DSS SetVMod (restore video mode)
        rst     #0x10
        pop     ix
        ld      a, (EVO_SAVED_SLOT0)
        out     (#0x82), a              ; restore WIN0 page register
        ld      a, #0xC0
        out     (#0x89), a              ; park PORT_Y
        ld      a, (EVO_EXIT_CODE)
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
        ; CBL control #004E enables #FE.5 video sync in evosdk_libs/video_vsync.s.
        ld      bc, #0x004E
        ld      a, #0x80
        out     (c), a

        ld      de, #0x8000
1$:
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        jr      nz, 2$
        dec     de
        ld      a, d
        or      e
        jr      nz, 1$
        jr      4$

2$:
        ld      de, #0x8000
3$:
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        jr      z, vsync_tick
        dec     de
        ld      a, d
        or      e
        jr      nz, 3$

4$:
        ei
        halt

vsync_tick:
        jp      inc_time_counter

_swap_screen::
        call    _vsync
        in      a, (#0xC9)              ; RGMOD bit 0: visible page A/B
        xor     #0x01
        and     #0x01
        out     (#0xC9), a
        ld      (_screen_active), a
        ret

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

clear_both_buffers_black:
        call    begin_vram_write
        ld      c, #0
        ld      hl, #0xC000
        call    fill_buffer_320x256
        ld      hl, #0xC140
        call    fill_buffer_320x256
        jp      end_vram_write

_clear_screen::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)
        call    begin_vram_write
        in      a, (#0xC9)              ; draw to hidden buffer = !visible
        and     #1
        xor     #1
        ld      hl, #0xC000
        jr      z, 1$
        ld      hl, #0xC140
1$:
        call    fill_buffer_320x256
        jp      end_vram_write

begin_vram_write::
        in      a, (#0xE2)
        ld      (_vram_saved_win3), a
        ld      a, #0x50                ; normal VRAM write, DRAM mirror updated
        out     (#0xE2), a
        ret

end_vram_write::
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_vram_saved_win3)
        out     (#0xE2), a
        ret

fill_buffer_320x256:
        ; In: HL = row base (#C000 visible A or #C140 visible B), C = color.
        ; Sprinter row window is selected by PORT_Y; 320 pixels are two
        ; 160-byte accel fills because the block-size latch is 8-bit.
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
        ld      b, b                    ; accel off
        ei

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
        ei

        pop     hl
        ret

; -------------------------------------------------------------------------
;  Palette (EvoSDK lib_startup zone). Direct protocol from HW_NOTES.md §3:
;  WIN3=#50, PORT_Y=index, #C3E0/#C3E1/#C3E2 = R/G/B (6-bit value in bits 7..2).
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
        ld      d, a
        ld      a, #0x50
        out     (#0xE2), a
        ld      b, #0
        xor     a
2$:
        ld      a, b
        out     (#0x89), a
        xor     a
        ld      (#0xC3E0), a
        ld      (#0xC3E1), a
        ld      (#0xC3E2), a
        djnz    2$
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, d
        out     (#0xE2), a
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
        ld      e, (hl)                 ; RGB222 color
        ld      b, #0
        ld      hl, #_palette
        add     hl, bc
        ld      (hl), e

        call    begin_palette_write
        ld      a, e
        call    write_palette_entry
        jp      end_palette_write

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
        ld      c, (hl)                 ; palette id
        xor     a                       ; EVOS type 0 = PAL
        call    find_asset_record
        jr      c, 2$
        ld      hl, #3
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        call    copy_palette_payload
        ret
2$:
        ld      hl, #3                  ; fallback: copy current palette
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      hl, #_palette
        ld      bc, #16
        ldir
        ret

_pal_select::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; palette id
        xor     a                       ; EVOS type 0 = PAL
        call    find_asset_record
        ret     c
        ld      de, #_palette
        call    copy_palette_payload
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

apply_palette_all:
        call    begin_palette_write
        ld      hl, #_palette
        ld      c, #0
1$:
        ld      a, (hl)
        push    hl
        call    write_palette_entry
        pop     hl
        inc     hl
        inc     c
        ld      a, c
        cp      #16
        jr      nz, 1$
        jp      end_palette_write

begin_palette_write:
        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #0x50
        out     (#0xE2), a
        ret

end_palette_write:
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
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
        pop     hl

        ld      a, e                    ; blue = bits 0..1
        and     #3
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E2), a
        pop     bc
        ret

; -------------------------------------------------------------------------
;  Asset bundle access (shared). find_asset_record returns a flat pointer
;  into the EVOS bundle at _evos_assets_ptr. NB: flat model -- works for the
;  Stage 2 low-loader (bundle <64KB in WIN1). The PRELOAD/paged loader will
;  rework payload addressing to page-map + window-offset (see HW_NOTES §14).
; -------------------------------------------------------------------------
find_asset_record::
        ; In: A = type, C = id. Out: NC+HL=payload, C if missing.
        ld      (_asset_find_type), a
        ld      a, c
        ld      (_asset_find_id), a

        ld      hl, (_evos_assets_ptr)
        ld      a, h
        or      l
        jr      z, asset_missing

        ld      de, #6
        add     hl, de
        ld      b, (hl)                 ; record_count low byte; enough for current EVOS
        ld      a, b
        or      a
        jr      z, asset_missing

        ld      hl, (_evos_assets_ptr)
        ld      de, #16                 ; first record
        add     hl, de
asset_find_loop:
        ld      a, (hl)
        ld      c, a
        ld      a, (_asset_find_type)
        cp      c
        jr      nz, asset_find_next
        inc     hl
        ld      c, (hl)
        dec     hl
        ld      a, (_asset_find_id)
        cp      c
        jr      z, asset_find_hit
asset_find_next:
        ld      de, #16
        add     hl, de
        djnz    asset_find_loop
asset_missing:
        scf
        ret

asset_find_hit:
        ld      (_asset_found_record), hl
        ld      de, #8                  ; record.offset low word
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      hl, (_evos_assets_ptr)
        add     hl, de
        or      a
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

        .area   _DATA
        ; DSS window/video state is saved by loader.asm to WIN2 #B400-#B401
        ; (cache-independent) and restored by the exit trampoline -- no _DATA
        ; copies here anymore.
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
_evos_assets_ptr:
        .dw     0
_evos_assets_len:
        .dw     0
_asset_find_type:
        .db     0
_asset_find_id:
        .db     0
_asset_found_record:
        .dw     0
