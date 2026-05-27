; =========================================================================
;  lib_sprites.asm -- sprite engine (EvoSDK responsibility zone)
; =========================================================================
;  Public API: set_sprite, sprites_start, sprites_stop.
;
;  M2b final path -- HARDWARE shadow VRAM + transparency (HW_NOTES §4, §5;
;  proven on real Sprinter, ref evosdk_libs/sprinter/lib/evo_sprite_*.s):
;    * Background is drawn through page #50 -> goes to BOTH the visible VRAM
;      plane and the hardware DRAM mirror. The mirror therefore always holds
;      clean background pixels.
;    * Sprites are drawn through page #5C (= #50 | TRANSPARENT 0x08 | VRAM_ONLY
;      0x04): the accelerator skips source bytes equal to 0xFF (hw transparency)
;      and writes ONLY to VRAM, never the mirror -- so the mirror stays clean.
;    * To erase last frame's sprites we copy clean pixels back from the mirror
;      to VRAM (page #50, same-address accel copy). No full-screen blit.
;  Each display buffer keeps its own saved-rect list (it is re-rendered every
;  other frame), mirroring EvoSDK's two sprite queues.
;
;  Hot loops use the Sprinter accelerator (HW_NOTES §4): LD D,D (#52) sets the
;  block size, LD L,L (#6D) copies a row, LD B,B (#40) disables it. The accel
;  requires interrupts off; Phase 1 runs fully DI (no EI -- HW_NOTES §7.1).
; =========================================================================

        .module lib_sprites

        .globl  _set_sprite
        .globl  _sprites_start
        .globl  _sprites_stop
        .globl  _sprites_render_before_swap
        .globl  _sprites_restore_after_swap
        .globl  _sprites_active         ; read by lib_tiles to gate tile-sync

        .area   _SDK

EVO_PAGE_TABLE = 0x1A00
EVO_META       = 0x1B00
EVP_GFX_PAGES  = EVO_META + 5

VRAM_PAGE      = 0x50                    ; write VRAM + DRAM mirror (background)
VRAM_PAGE_SPR  = 0x5C                    ; transparent + VRAM-only (sprites)
VRAM_BUF0_BASE = 0xC000
VRAM_BUF1_BASE = 0xC140
VRAM_Y_OFFSET  = 28                      ; center the 200-row EvoSDK surface

; -------------------------------------------------------------------------
; void set_sprite(u8 id, u8 x, u8 y, u16 spr)
; Queue format matches EvoSDK: idh, idl, y, x. SPRITE_END is idh=#FF.
; X is in 2-pixel units, Y is in pixels.
; -------------------------------------------------------------------------
_set_sprite::
        push    iy
        ld      iy, #4
        add     iy, sp

        ld      a, 0 (iy)               ; queue slot id 0..63
        and     #0x3F
        ld      l, a
        ld      h, #0
        add     hl, hl
        add     hl, hl                  ; id * 4
        ld      de, #_sprqueue
        add     hl, de

        ld      a, 4 (iy)               ; spr high
        ld      (hl), a
        inc     hl
        ld      a, 3 (iy)               ; spr low
        ld      (hl), a
        inc     hl
        ld      a, 2 (iy)               ; y
        ld      (hl), a
        inc     hl
        ld      a, 1 (iy)               ; x
        ld      (hl), a

        pop     iy
        ret

; -------------------------------------------------------------------------
; sprites_start()
; The caller drew a clean background to the visible page and swapped it in.
; Copy that background to the hidden page (page #50 -> hidden VRAM + mirror)
; so both buffers and both mirrors start with clean background, then clear the
; per-buffer saved-rect lists and enable rendering.
; -------------------------------------------------------------------------
_sprites_start::
        xor     a
        ld      (_sprites_active), a

        ; clear sprite queue to end markers
        ld      hl, #_sprqueue
        ld      de, #_sprqueue + 1
        ld      bc, #255
        ld      (hl), #0xFF
        ldir

        ; clear saved-valid flags for both buffers (64 each)
        ld      hl, #_spr_saved_valid
        ld      de, #_spr_saved_valid + 1
        ld      bc, #127
        ld      (hl), #0
        ldir

        di                              ; accel needs interrupts off
        in      a, (#0xE2)
        ld      (_spr_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a

        in      a, (#0xC9)
        and     #1
        ld      hl, #VRAM_BUF0_BASE      ; visible 0 -> hidden 1
        ld      de, #VRAM_BUF1_BASE
        jr      z, sprites_start_copy
        ex      de, hl                  ; visible 1 -> hidden 0
sprites_start_copy:
        ld      a, #VRAM_Y_OFFSET
sprites_start_row:
        out     (#0x89), a
        push    af
        push    hl
        push    de
        call    accel_copy_row_320
        pop     de
        pop     hl
        pop     af
        inc     a
        cp      #VRAM_Y_OFFSET + 200
        jr      nz, sprites_start_row

        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a

        ld      a, #1
        ld      (_sprites_active), a
        ret

_sprites_stop::
        xor     a
        ld      (_sprites_active), a
        ret

; -------------------------------------------------------------------------
; sprites_render_before_swap()
; Called by swap_screen (before vsync/flip). Renders into the hidden (back)
; buffer: erase last frame's sprites from the mirror, draw the current queue
; through the transparent VRAM-only page. swap_screen then flips it in.
; -------------------------------------------------------------------------
_sprites_render_before_swap::
        ld      a, (_sprites_active)
        or      a
        ret     z
        di                              ; accel requires interrupts off (Phase 1 = DI)

        ; back buffer = visible ^ 1; base = #C000 (buf0) / #C140 (buf1)
        in      a, (#0xC9)
        and     #1
        xor     #1
        ld      (_spr_back), a
        ld      hl, #VRAM_BUF0_BASE
        or      a
        jr      z, render_base_ok
        ld      hl, #VRAM_BUF1_BASE
render_base_ok:
        ld      (_spr_base), hl

        ; save windows (WIN1 = C code, WIN3 = C heap -- both restored at end)
        in      a, (#0xA2)
        ld      (_spr_win1), a
        in      a, (#0xE2)
        ld      (_spr_win3), a

; ---- DRAW: blit the current queue through #5C (transparent, VRAM-only). ----
; The back buffer is already clean here: _sprites_restore_after_swap erased its
; previous-frame sprites (from the mirror) right after the last flip, so a
; restore pass before drawing would be a no-op. Single restore point = less work
; per frame and no double-restore interaction.
        call    select_saved_arrays     ; -> _spr_vptr / _spr_xptr / _spr_yptr
        ld      hl, #_sprqueue
        ld      (_spr_qptr), hl
        ld      a, #VRAM_PAGE_SPR
        out     (#0xE2), a

draw_loop:
        ld      hl, (_spr_qptr)
        ld      a, (hl)                 ; idh, #FF = end of queue
        cp      #0xFF
        jp      z, draw_done
        inc     hl
        ld      a, (hl)                 ; idl = sprite id (0..255)
        ld      (_spr_id), a
        inc     hl
        ld      a, (hl)                 ; y
        ld      (_spr_yraw), a
        inc     hl
        ld      a, (hl)                 ; x (2-pixel units)
        ld      (_spr_xraw), a

        ; py = y + 28; skip if y + 16 would leave the 256-row frame.
        ld      a, (_spr_yraw)
        add     a, #VRAM_Y_OFFSET
        cp      #241
        jr      nc, draw_skip
        ld      (_spr_py), a

        ; x*2 byte offset; skip if it would run past the 320-px right edge.
        ld      a, (_spr_xraw)
        cp      #153                    ; x*2 >= 306 -> +16 > 320
        jr      nc, draw_skip
        ld      l, a
        ld      h, #0
        add     hl, hl                  ; x*2 (16-bit)
        ld      bc, (_spr_base)
        add     hl, bc
        ld      (_spr_dest), hl

        ; WIN1 = page_table[gfx_pages + (id >> 6)]
        ld      a, (_spr_id)
        rlca
        rlca
        and     #0x03                   ; id >> 6
        ld      c, a
        ld      a, (EVP_GFX_PAGES)
        add     a, c
        ld      l, a
        ld      h, #0
        ld      bc, #EVO_PAGE_TABLE
        add     hl, bc
        ld      a, (hl)
        out     (#0xA2), a

        ; source = #4000 + (id & 63) * 256
        ld      a, (_spr_id)
        and     #0x3F
        add     a, #0x40
        ld      h, a
        ld      l, #0

        ld      de, (_spr_dest)
        ld      a, (_spr_py)
        call    blit_one_16x16          ; HL = source, DE = VRAM dest, A = PORT_Y

        ; record the rect so the next pass over this buffer can erase it
        ld      hl, (_spr_xptr)
        ld      a, (_spr_xraw)
        ld      (hl), a
        ld      hl, (_spr_yptr)
        ld      a, (_spr_py)
        ld      (hl), a
        ld      hl, (_spr_vptr)
        ld      (hl), #1

draw_advance:
        call    advance_saved_ptrs
        ld      hl, (_spr_qptr)
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      (_spr_qptr), hl
        jp      draw_loop

draw_skip:
        ; out of range: leave saved_valid clear (already cleared by restore).
        jr      draw_advance

draw_done:
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a
        ld      a, (_spr_win1)
        out     (#0xA2), a
        ret

; -------------------------------------------------------------------------
; sprites_restore_after_swap()
; EvoSDK restores the old visible screen immediately after flipping it to the
; shadow buffer (evosdk/lib_startup.asm: _swap_screen -> respr). Do the same
; here: after RGMOD.0 was toggled, the hidden buffer is visible^1 and may still
; contain sprites from the previous frame. Restore only saved rectangles from
; the clean hardware mirror so a later non-sprite swap cannot show stale masks.
; -------------------------------------------------------------------------
_sprites_restore_after_swap::
        ld      a, (_sprites_active)
        or      a
        ret     z
        di

        in      a, (#0xE2)
        ld      (_spr_win3), a

        in      a, (#0xC9)
        and     #1
        xor     #1
        ld      (_spr_back), a
        ld      hl, #VRAM_BUF0_BASE
        or      a
        jr      z, restore_after_base_ok
        ld      hl, #VRAM_BUF1_BASE
restore_after_base_ok:
        ld      (_spr_base), hl

        call    select_saved_arrays
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    restore_saved_rects

        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a
        ret

; -------------------------------------------------------------------------
; select_saved_arrays: point _spr_vptr/_spr_xptr/_spr_yptr at the saved-rect
; slice for the current back buffer (offset +64 for buffer 1).
; -------------------------------------------------------------------------
select_saved_arrays:
        ld      hl, #_spr_saved_valid
        ld      de, #_spr_saved_x
        ld      bc, #_spr_saved_py
        ld      a, (_spr_back)
        or      a
        jr      z, save_sel_ok
        ld      hl, #_spr_saved_valid + 64
        ld      de, #_spr_saved_x + 64
        ld      bc, #_spr_saved_py + 64
save_sel_ok:
        ld      (_spr_vptr), hl
        ld      (_spr_xptr), de
        ld      (_spr_yptr), bc
        ret

advance_saved_ptrs:
        ld      hl, (_spr_vptr)
        inc     hl
        ld      (_spr_vptr), hl
        ld      hl, (_spr_xptr)
        inc     hl
        ld      (_spr_xptr), hl
        ld      hl, (_spr_yptr)
        inc     hl
        ld      (_spr_yptr), hl
        ret

restore_saved_rects:
        ld      a, #64
        ld      (_spr_cnt), a
restore_loop:
        ld      hl, (_spr_vptr)
        ld      a, (hl)
        or      a
        jr      z, restore_next
        ld      (hl), #0                ; consume this saved rect

        ld      hl, (_spr_yptr)
        ld      a, (hl)
        ld      (_spr_py), a

        ld      hl, (_spr_xptr)
        ld      a, (hl)
        ld      l, a
        ld      h, #0
        add     hl, hl                  ; x*2 (16-bit)
        ld      bc, (_spr_base)
        add     hl, bc                  ; HL = VRAM column
        ld      a, (_spr_py)
        call    restore_one_16x16
restore_next:
        call    advance_saved_ptrs
        ld      hl, #_spr_cnt
        dec     (hl)
        jr      nz, restore_loop
        ret

; -------------------------------------------------------------------------
; restore_one_16x16: HL = VRAM column base, A = first PORT_Y.
; Page #50 in WIN3. Same-address accel copy reads the clean DRAM mirror and
; writes it back to VRAM, 16 bytes per scanline for 16 rows. Ref
; evosdk_libs/sprinter/lib/evo_sprite_bg.s.
; -------------------------------------------------------------------------
restore_one_16x16:
        ld      e, a                    ; E = PORT_Y
        ld      c, #16                  ; rows left
restore_row:
        ld      a, e
        out     (#0x89), a
        ld      d, d                    ; accel: set block size
        ld      a, #16
        ld      l, l                    ; accel: copy row (mirror -> VRAM)
        ld      a, (hl)
        ld      (hl), a
        ld      b, b                    ; accel: off
        inc     e
        dec     c
        jr      nz, restore_row
        ret

; -------------------------------------------------------------------------
; blit_one_16x16: HL = source (WIN1 sprite cell), DE = VRAM dest, A = PORT_Y.
; Page #5C in WIN3 -> hardware skips 0xFF bytes (transparency) and leaves the
; DRAM mirror untouched. 16 bytes per scanline for 16 rows; source advances one
; row (16 bytes) each line. Ref evosdk_libs/sprinter/lib/evo_sprite_blit.s.
; -------------------------------------------------------------------------
blit_one_16x16:
        ld      b, a                    ; B = PORT_Y
        ld      c, #16                  ; rows left
blit_row:
        ld      a, b
        out     (#0x89), a
        ld      d, d                    ; accel: set block size
        ld      a, #16
        ld      l, l                    ; accel: copy row (HL -> DE)
        ld      a, (hl)
        ld      (de), a
        ld      b, b                    ; accel: off
        ld      a, #16                  ; source += 16 (next sprite row)
        add     a, l
        ld      l, a
        jr      nc, blit_src_ok
        inc     h
blit_src_ok:
        inc     b                       ; next scanline
        dec     c
        jr      nz, blit_row
        ret

; -------------------------------------------------------------------------
; accel_copy_row_320: HL = source, DE = dest (both within the current PORT_Y
; row, page #50). Copies 320 bytes as two 160-byte accel pulses (the block-size
; latch is 8-bit). Does not preserve HL/DE. Ref evo_sync_buffers.s.
; -------------------------------------------------------------------------
accel_copy_row_320:
        ld      d, d
        ld      a, #160
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b

        ld      a, #160                 ; advance both pointers by 160
        add     a, l
        ld      l, a
        jr      nc, copy_row_hl_ok
        inc     h
copy_row_hl_ok:
        ld      a, #160
        add     a, e
        ld      e, a
        jr      nc, copy_row_de_ok
        inc     d
copy_row_de_ok:
        ld      d, d
        ld      a, #160
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        ret

        .area   _SDKDATA
_sprites_active:
        .db     0
_spr_win1:
        .db     0
_spr_win3:
        .db     0
_spr_back:
        .db     0
_spr_base:
        .dw     0
_spr_vptr:
        .dw     0
_spr_xptr:
        .dw     0
_spr_yptr:
        .dw     0
_spr_qptr:
        .dw     0
_spr_id:
        .db     0
_spr_xraw:
        .db     0
_spr_yraw:
        .db     0
_spr_py:
        .db     0
_spr_dest:
        .dw     0
_spr_cnt:
        .db     0
; Per-buffer saved sprite rects (buffer 0 = [0..63], buffer 1 = [64..127]).
_spr_saved_valid:
        .ds     128
_spr_saved_x:
        .ds     128
_spr_saved_py:
        .ds     128
_sprqueue:
        .ds     256
