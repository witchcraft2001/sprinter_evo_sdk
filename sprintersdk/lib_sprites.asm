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
        .if SPRITE16
        .globl  _draw_sprite16          ; opt-in immediate-mode 16x16 blit (SPRITE16=1)
        .endif

        .area   _SDK

EVO_PAGE_TABLE = 0x1A00
EVO_META       = 0x1B00
EVP_GFX_PAGES  = EVO_META + 5

VRAM_PAGE      = 0x50                    ; write VRAM + DRAM mirror (background)
VRAM_PAGE_SPR  = 0x5C                    ; transparent + VRAM-only (sprites)
VRAM_BUF0_BASE = 0xC000
VRAM_BUF1_BASE = 0xC140
        .if NATIVE
VRAM_Y_OFFSET  = 0                       ; native: full 320x256 surface, no centering
SURFACE_ROWS   = 256
        .else
VRAM_Y_OFFSET  = 28                      ; compat: centre the 200-row EvoSDK surface
SURFACE_ROWS   = 200
        .endif
; Sprite X is a full 16-bit value in both modes (set_sprite takes u16 x). Compat
; stores 0..152 and the byte dest offset is x*2 (XSHIFT=1, EvoSDK 2px granularity);
; native stores 0..319 and the offset is x (XSHIFT=0, per-pixel over the full width).
; The `.if NATIVE` blocks below pick the shift; X clipping is one 16-bit compare.
QSTRIDE        = 5                       ; queue record: idh, idl, y, xlo, xhi
SSTRIDE        = 4                       ; saved rect:   valid, py, xlo, xhi

; -------------------------------------------------------------------------
; void set_sprite(u8 id, u16 x, u8 y, u16 spr)
; Queue record (QSTRIDE=5): idh, idl, y, xlo, xhi. SPRITE_END is idh=#FF.
; X is 16-bit: compat = 2-pixel units (0..152), native = pixels (0..319). Y in pixels.
; Args on stack (ascending): id @0, x @1-2, y @3, spr @4-5.
; -------------------------------------------------------------------------
_set_sprite::
        push    iy
        ld      iy, #4
        add     iy, sp

        ld      a, 0 (iy)               ; queue slot id 0..63
        and     #0x3F
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = id
        add     hl, hl
        add     hl, hl                  ; id*4
        add     hl, de                  ; id*5 (QSTRIDE)
        ld      de, #_sprqueue
        add     hl, de

        ld      a, 5 (iy)               ; spr high -> idh
        ld      (hl), a
        inc     hl
        ld      a, 4 (iy)               ; spr low  -> idl
        ld      (hl), a
        inc     hl
        ld      a, 3 (iy)               ; y
        ld      (hl), a
        inc     hl
        ld      a, 1 (iy)               ; x low
        ld      (hl), a
        inc     hl
        ld      a, 2 (iy)               ; x high
        ld      (hl), a

        pop     iy
        ret

        .if SPRITE16
; -------------------------------------------------------------------------
; void draw_sprite16(u16 x, u8 y, u16 spr, u8 flags)   [Sprinter-only, opt-in]
; Immediate-mode masked accel blit of one 16x16 cell straight into the HIDDEN
; buffer at pixel coordinates -- NO queue slot, NO 64-sprite limit. Reuses the
; engine's blit_one_16x16 through a VRAM-ONLY page (#5C transparent / #54 opaque)
; so the DRAM mirror (used by the tile- and sprite-list restore paths) stays
; clean. The background is NOT auto-restored: the caller redraws it every frame
; (hybrid render). flags bit0: 0 = transparent (skip index 255), 1 = opaque.
; spr 0..255. Fully off-screen (x>=305 or py+16>256) is skipped, like the list.
; Enabled by SPRITE16=1 (sprinter.mk); absent and zero-cost otherwise.
; -------------------------------------------------------------------------
_draw_sprite16::
        push    ix
        ld      ix, #4
        add     ix, sp                  ; IX -> args: x(0,1) y(2) spr(3,4) flags(5)

        ld      l, 0 (ix)               ; x_px (per-pixel byte offset)
        ld      h, 1 (ix)
        push    hl                      ; clip: skip if x_px + 16 > 320 (x_px >= 305)
        ld      de, #305
        or      a
        sbc     hl, de
        pop     hl                      ; HL = x_px, CF set if on-screen
        jr      nc, ds16_done

        ld      a, 2 (ix)               ; py = y + VRAM_Y_OFFSET
        add     a, #VRAM_Y_OFFSET
        cp      #241                    ; skip if py + 16 > 256
        jr      nc, ds16_done
        ld      c, a                    ; C = py (PORT_Y for blit)

        di                              ; accelerator requires interrupts off
        in      a, (#0xA2)
        ld      (_spr_win1), a          ; save WIN1 (C code) / WIN3 (C heap)
        in      a, (#0xE2)
        ld      (_spr_win3), a

        ; dest column = hidden buffer base + x_px
        push    hl                      ; save x_px
        in      a, (#0xC9)              ; RGMOD bit0 = visible buffer
        and     #1
        xor     #1                      ; hidden = visible ^ 1
        ld      hl, #VRAM_BUF0_BASE
        jr      z, ds16_base_ok
        ld      hl, #VRAM_BUF1_BASE
ds16_base_ok:
        pop     de                      ; DE = x_px
        add     hl, de
        push    hl                      ; dest -> blit wants it in DE

        ld      a, 5 (ix)               ; flags bit0: 0 transparent, 1 opaque
        rrca
        ld      a, #VRAM_PAGE_SPR       ; #5C transparent + VRAM-only
        jr      nc, ds16_pg_ok
        ld      a, #0x54                ; #54 opaque + VRAM-only
ds16_pg_ok:
        out     (#0xE2), a              ; WIN3 = sprite page

        ld      a, 3 (ix)               ; WIN1 = page_table[gfx_pages + (spr>>6)]
        rlca
        rlca
        and     #0x03
        ld      e, a
        ld      a, (EVP_GFX_PAGES)
        add     a, e
        ld      e, a
        ld      d, #0
        ld      hl, #EVO_PAGE_TABLE
        add     hl, de
        ld      a, (hl)
        out     (#0xA2), a

        ld      a, 3 (ix)               ; source = #4000 + (spr & 63) * 256
        and     #0x3F
        add     a, #0x40
        ld      h, a
        ld      l, #0

        pop     de                      ; DE = dest
        ld      a, c                    ; A = py (PORT_Y)
        call    blit_one_16x16

        ld      a, (_spr_win3)          ; restore windows + PORT_Y
        out     (#0xE2), a
        ld      a, (_spr_win1)
        out     (#0xA2), a
        ld      a, #0xC0
        out     (#0x89), a
        ei
ds16_done:
        pop     ix
        ret
        .endif

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

        ; clear sprite queue to end markers (64 * QSTRIDE = 320 bytes -> all idh=#FF)
        ld      hl, #_sprqueue
        ld      de, #_sprqueue + 1
        ld      bc, #64 * QSTRIDE - 1
        ld      (hl), #0xFF
        ldir

        ; clear all per-buffer saved-rect structs (64 slots * SSTRIDE * 2 buffers)
        ld      hl, #_spr_saved
        ld      de, #_spr_saved + 1
        ld      bc, #64 * SSTRIDE * 2 - 1
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
        .if NATIVE
        jr      nz, sprites_start_row        ; full 256 rows: A wraps 255 -> 0
        .else
        cp      #VRAM_Y_OFFSET + SURFACE_ROWS ; compat: 28..228 (200 rows)
        jr      nz, sprites_start_row
        .endif

        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a

        ld      a, #1
        ld      (_sprites_active), a
        ei                              ; re-enable IM2 (sound); accel block done
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
        push    ix                      ; IX/IY hold the saved-struct + queue ptrs
        push    iy                      ; across the loop; restore for the C caller

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
; previous-frame sprites after the last flip. IY = queue entry, IX = saved-rect
; struct for this buffer -- both survive the blit calls, so the per-sprite loop
; touches no scratch RAM. The rect is recorded BEFORE the blit (which clobbers
; the main registers).
        call    saved_base_hl           ; HL = saved-struct base for this buffer
        push    hl
        pop     ix                      ; IX = saved struct (advances +SSTRIDE / sprite)
        ld      iy, #_sprqueue          ; IY = queue entry (advances +QSTRIDE / sprite)
        ld      a, #VRAM_PAGE_SPR
        out     (#0xE2), a

draw_loop:
        .if SAMPLE_ASYNC
        ei                              ; open an IRQ window (CBL refill / music) for
        .endif                          ; the non-accel per-sprite setup below; DI is
                                        ; re-asserted just before the accel blit.
        ld      a, 0 (iy)               ; idh, #FF = end of queue
        cp      #0xFF
        jp      z, draw_done

        ; x_px = x << XSHIFT (HL); clip if x_px + 16 > 320 (i.e. x_px >= 305)
        ld      l, 3 (iy)               ; x low
        ld      h, 4 (iy)               ; x high
        .if NATIVE
        .else
        add     hl, hl                  ; compat: x*2 (2-pixel units)
        .endif
        push    hl                      ; keep x_px (back-buffer byte offset)
        ld      de, #305
        or      a
        sbc     hl, de                  ; CF set (borrow) if x_px < 305 -> on screen
        pop     hl                      ; HL = x_px (flags from sbc preserved)
        jr      nc, draw_skip           ; x_px >= 305 -> off right edge, skip

        ld      a, 2 (iy)               ; y
        add     a, #VRAM_Y_OFFSET       ; py
        cp      #241                    ; py + 16 > 256: skip
        jr      nc, draw_skip

        ld      1 (ix), a               ; saved py
        ld      b, a                    ; B = py (PORT_Y for blit)
        ld      a, #1
        ld      0 (ix), a               ; saved valid = 1
        ld      a, 3 (iy)
        ld      2 (ix), a               ; saved x low
        ld      a, 4 (iy)
        ld      3 (ix), a               ; saved x high

        ; dest = back-buffer base + x_px (HL already = x_px)
        ld      de, (_spr_base)
        add     hl, de
        push    hl                      ; dest (blit wants it in DE)

        ; WIN1 = page_table[gfx_pages + (id >> 6)]
        ld      a, 1 (iy)               ; id
        rlca
        rlca
        and     #0x03
        ld      e, a
        ld      a, (EVP_GFX_PAGES)
        add     a, e
        ld      e, a
        ld      d, #0
        ld      hl, #EVO_PAGE_TABLE
        add     hl, de
        ld      a, (hl)
        out     (#0xA2), a

        ; source = #4000 + (id & 63) * 256
        ld      a, 1 (iy)               ; id
        and     #0x3F
        add     a, #0x40
        ld      h, a
        ld      l, #0

        pop     de                      ; DE = dest
        ld      a, b                    ; A = py (PORT_Y)
        .if SAMPLE_ASYNC
        di                              ; close the IRQ window before the accel blit
        .endif
        call    blit_one_16x16

draw_next:
        ld      bc, #SSTRIDE
        add     ix, bc                  ; next saved struct
        ld      bc, #QSTRIDE
        add     iy, bc                  ; next queue entry
        jp      draw_loop

draw_skip:
        ld      bc, #SSTRIDE            ; out of range: leave valid (already 0)
        add     ix, bc
        ld      bc, #QSTRIDE
        add     iy, bc
        jp      draw_loop

draw_done:
        .if SAMPLE_ASYNC
        di                              ; structural cleanup runs with IRQs off
        .endif
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a
        ld      a, (_spr_win1)
        out     (#0xA2), a
        pop     iy
        pop     ix
        ei                              ; re-enable IM2 (sound); accel block done
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
        push    ix                      ; restore_saved_rects walks IX

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

        call    saved_base_hl
        push    hl
        pop     ix                      ; IX = saved struct base
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    restore_saved_rects
        .if SAMPLE_ASYNC
        di                              ; loop may have left IRQs on; cleanup runs DI
        .endif

        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_spr_win3)
        out     (#0xE2), a
        pop     ix
        ei                              ; re-enable IM2 (sound); accel block done
        ret

; -------------------------------------------------------------------------
; saved_base_hl: HL = base of the saved-rect struct array for the current back
; buffer (_spr_back). Buffer 1 is offset by 64 slots * SSTRIDE bytes.
; -------------------------------------------------------------------------
saved_base_hl:
        ld      hl, #_spr_saved
        ld      a, (_spr_back)
        or      a
        ret     z
        ld      hl, #_spr_saved + 64 * SSTRIDE
        ret

; restore_saved_rects: IX = saved struct base. For each of 64 slots with valid=1,
; copy its 16x16 background back from the mirror and clear valid. B = counter.
; restore_one_16x16 preserves B and IX; _spr_base gives the buffer base.
; Saved rect = { valid(0), py(1), xlo(2), xhi(3) }.
restore_saved_rects:
        ld      b, #64
restore_loop:
        .if SAMPLE_ASYNC
        ei                              ; IRQ window during the non-accel rect setup
        .endif
        ld      a, 0 (ix)               ; valid
        or      a
        jr      z, restore_next
        xor     a
        ld      0 (ix), a               ; consume (valid = 0)
        ld      l, 2 (ix)               ; x low
        ld      h, 3 (ix)               ; x high
        .if NATIVE
        .else
        add     hl, hl                  ; compat: x*2
        .endif
        ld      de, (_spr_base)
        add     hl, de                  ; HL = VRAM column (x_px)
        ld      a, 1 (ix)               ; py
        .if SAMPLE_ASYNC
        di                              ; close the IRQ window before the accel copy
        .endif
        call    restore_one_16x16
restore_next:
        ld      de, #SSTRIDE
        add     ix, de                  ; next saved struct
        djnz    restore_loop
        ret

; -------------------------------------------------------------------------
; restore_one_16x16: HL = VRAM column base, A = first PORT_Y.
; Page #50 in WIN3. Same-address accel copy reads the clean DRAM mirror and
; writes it back to VRAM, 16 bytes per scanline for 16 rows. Ref
; evosdk_libs/sprinter/lib/evo_sprite_bg.s.
; -------------------------------------------------------------------------
restore_one_16x16:
        ld      e, a                    ; E = PORT_Y
        .if UNROLL
        ; --- 16 rows unrolled: HL = mirror/VRAM column (constant), E = PORT_Y++. ---
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        inc     e
        ld      a, e
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (hl), a
        ld      b, b
        ret
        .else
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
        .endif

; -------------------------------------------------------------------------
; blit_one_16x16: HL = source (WIN1 sprite cell), DE = VRAM dest, A = PORT_Y.
; Page #5C in WIN3 -> hardware skips 0xFF bytes (transparency) and leaves the
; DRAM mirror untouched. 16 bytes per scanline for 16 rows; source advances one
; row (16 bytes) each line. Ref evosdk_libs/sprinter/lib/evo_sprite_blit.s.
; -------------------------------------------------------------------------
blit_one_16x16:
        ld      b, a                    ; B = PORT_Y
        .if UNROLL
        ; --- 16 rows unrolled. Within a 256-byte sprite cell the source low byte
        ;     is 0,16,..,240 with H constant, so set L directly per row (no add/
        ;     carry/inc h). DE (dest) is constant; B = PORT_Y++. ---
        ld      l, #0
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #16
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #32
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #48
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #64
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #80
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #96
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #112
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #128
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #144
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #160
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #176
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #192
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #208
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #224
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      l, #240
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #16
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        ret
        .else
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
        .endif

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
; Per-buffer saved sprite rects -- one struct per slot: { valid, py, xlo, xhi } (SSTRIDE).
; Buffer 0 = slots [0..63] at +0, buffer 1 = slots [0..63] at +64*SSTRIDE. Walked with
; IX in the draw/restore loops (queue ptr is IY, per-sprite temps are registers).
_spr_saved:
        .ds     64 * SSTRIDE * 2
_sprqueue:
        .ds     64 * QSTRIDE
