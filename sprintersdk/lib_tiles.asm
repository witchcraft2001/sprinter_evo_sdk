; =========================================================================
;  lib_tiles.asm -- tile / image output (EvoSDK responsibility zone)
; =========================================================================
;  Public API: select_image, color_key, draw_tile, draw_tile_key, draw_image.
;  Mirrors evosdk/lib_tiles.asm.
;
;  Paged (EVP1) O(1) model -- HW_NOTES §9.2, §15:
;    global_tile = img[id].base_tile + tile
;    gfx page    = page_table[global_tile >> 8]   (mapped into WIN1)
;    src in page = (global_tile & 255) * 64        (#4000 + that)
;    VRAM dest   = hidden buffer in WIN3 page #50, row selected by PORT_Y.
;  The SDK runs from SRAM (WIN0); draw_tile saves/maps/restores WIN1 (gfx) and
;  WIN3 (VRAM). All scratch + the loader-filled tables (page table #1A00, EVP1
;  meta #1B00) live in the SDK SRAM region -- WIN0 is never remapped by a draw.
; =========================================================================

        .module lib_tiles

        .globl  _select_image
        .globl  _color_key
        .globl  _draw_tile
        .globl  _draw_tile_key
        .globl  _draw_image
        .globl  _sync_tiles_to_shadow   ; called by swap_screen (lib_startup)

        ; --- imported from lib_startup.asm ---
        .globl  begin_vram_write
        .globl  end_vram_write
        .globl  _vram_base              ; back buffer base (#C000/#C140)
        ; --- imported from lib_sprites.asm ---
        .globl  _sprites_active         ; tile-sync runs only while sprites active

; --- loader-filled runtime tables in the SDK SRAM region. MUST match loader.asm
;     and lib_startup.asm. ---
EVO_PAGE_TABLE = 0x1A00                 ; phys page numbers, index = logical page
EVO_IMG_TABLE  = 0x1B11                 ; EVO_META(#1B00)+16 hdr +1 img_count byte
                                        ; records: { u16 base_tile, u8 wt, u8 ht, u8 flags }
VRAM_PAGE      = 0x50                    ; VRAM + DRAM mirror (read = mirror)
VRAM_BUF0_BASE = 0xC000
VRAM_BUF1_BASE = 0xC140
        .if NATIVE
VRAM_Y_OFFSET  = 0                      ; native: full 320x256 surface, no centering
TILE_DIRTY_ROWS  = 32                   ; 256px / 8
        .else
VRAM_Y_OFFSET  = 28                     ; compat: centre the 200-row EvoSDK surface
TILE_DIRTY_ROWS  = 25                   ; 200px / 8
        .endif
TILE_DIRTY_STRIDE = 5                   ; 40 cells / 8 bits

        .area   _SDK

_select_image::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; image id
select_image_a:
        ; record = EVO_IMG_TABLE + id*5: { u16 base_tile, u8 wt, u8 ht, u8 flags }
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = id
        add     hl, hl
        add     hl, hl                  ; id*4
        add     hl, de                  ; id*5
        ld      de, #EVO_IMG_TABLE
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; de = base_tile (full u16, flag is elsewhere)
        ld      (_image_base_tile), de
        inc     hl
        ld      a, (hl)                 ; w in tiles
        ld      (_image_width_tiles), a
        inc     hl
        ld      a, (hl)                 ; h in tiles
        ld      (_image_height_tiles), a
        inc     hl
        ld      a, (hl)                 ; flags byte
        and     #0x01                   ; bit0 -> hw_keyed (1 / 0)
        ld      (_image_hw_keyed), a
        ld      a, #1
        ld      (_image_selected), a
        ret

_color_key::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (_color_key_value), a
        ret

_draw_tile_key::
        ld      a, (_image_selected)
        or      a
        ret     z

        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; x in 8px tiles
        inc     hl
        ld      b, (hl)                 ; y in 8px tiles
        inc     hl
        ld      e, (hl)                 ; tile low
        inc     hl
        ld      d, (hl)                 ; tile high
        call    draw_tile_setup
        ld      a, (_image_hw_keyed)
        or      a
        jp      z, draw_tile_keyed_rows ; runtime key -> CPU compare/skip
        ; hw_keyed image: the transparent index was baked to 0xFF at pack time.
        ; Switch WIN3 to #58 (HW drops 0xFF + DRAM mirror still updates, so the
        ; sprite background restore stays coherent) and blit with the fast
        ; unrolled LDI burst -- no per-pixel CPU compare. ~6x faster.
        ld      a, #0x58
        out     (#0xE2), a
        jp      draw_tile_unkeyed_rows

_draw_tile::
        ld      a, (_image_selected)
        or      a
        ret     z

        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; x in 8px tiles
        inc     hl
        ld      b, (hl)                 ; y in 8px tiles
        inc     hl
        ld      e, (hl)                 ; tile low
        inc     hl
        ld      d, (hl)                 ; tile high

draw_tile_core:
        ; In: C = x tile, B = y tile, DE = tile index. Image is selected.
        call    draw_tile_setup
        jp      draw_tile_unkeyed_rows

draw_tile_setup:
        ; In: C = x tile, B = y tile, DE = tile index. Image is selected.
        ; Out: WIN1 = source gfx page, WIN3 = VRAM #50, _draw_src/_draw_y and
        ;      dest patches prepared. Caller must draw rows, call end_vram_write
        ;      and restore WIN1 from _draw_saved_win1.
        call    mark_tile_dirty         ; record cell (C,B) for buffer sync on swap
        ld      l, c
        ld      h, #0
        add     hl, hl
        add     hl, hl
        add     hl, hl                  ; x*8 (0..312), must stay 16-bit
        ld      (draw_dest_x_patch + 1), hl
        ld      a, b
        add     a, a
        add     a, a
        add     a, a                    ; y*8 (pixel row in the surface)
        add     a, #VRAM_Y_OFFSET       ; centre offset (28 compat / 0 native)
        ld      (_draw_y), a

        ; global tile = base_tile + tile
        ld      hl, (_image_base_tile)
        add     hl, de                  ; HL = global tile
        ; phys gfx page = page_table[global >> 8]
        ld      a, h
        ld      c, a
        ld      b, #0
        push    hl                      ; keep global (L = in-page tile)
        ld      hl, #EVO_PAGE_TABLE
        add     hl, bc
        ld      a, (hl)
        ld      (_draw_gfx_page), a
        pop     hl
        ; src offset = (global & 255) * 64
        ld      h, #0                   ; HL = in-page tile (0..255)
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl                  ; *64
        ld      de, #0x4000
        add     hl, de                  ; WIN1 source
        ld      (_draw_src), hl

        ; save + map WIN1 to the gfx page (SDK runs from SRAM, safe to remap)
        in      a, (#0xA2)
        ld      (_draw_saved_win1), a
        ld      a, (_draw_gfx_page)
        out     (#0xA2), a

        call    begin_vram_write        ; WIN3 = #50, _vram_base = hidden base

        ; VRAM dest = hidden-buffer base (#C000/#C140) + x*8.
        ; Single page #50; PORT_Y selects the scanline.
draw_dest_x_patch:
        ld      bc, #0
        ld      hl, (_vram_base)
        add     hl, bc
        ld      (draw_dest_patch + 1), hl
        ld      (draw_tile_keyed_dest_patch + 1), hl

        ld      hl, (_draw_src)         ; HL = source row; persists, advances 8/row
        ret

; --- Unkeyed rows: PORT_Y lives in A the whole time (LDI does not touch A), and
;     the loop terminates when PORT_Y reaches start+8 -- no separate counter, no
;     EXX, no per-row memory access. Main BC is free for the LDI burst. ---
draw_tile_unkeyed_rows:
        .if UNROLL
        ; --- 8 rows unrolled. A = PORT_Y (preserved across LDI); HL (src) advances
        ;     via LDI; DE is reset to the dest column each row (LDI advances it).
        ;     Row 0 holds the setup-patched dest immediate; rows 1-7 read it back.
        ;     Drops the per-row PORT_Y compare + jr. ---
        ld      a, (_draw_y)            ; A = PORT_Y
        out     (#0x89), a
        inc     a
draw_dest_patch:
        ld      de, #0                  ; dest column base (patched by setup)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        inc     a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        out     (#0x89), a
        ld      de, (draw_dest_patch + 1)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        call    end_vram_write
        ld      a, (_draw_saved_win1)   ; restore WIN1 (C code lives there)
        out     (#0xA2), a
        ret
        .else
        ld      a, (_draw_y)
        add     a, #8
        ld      (draw_tile_unkeyed_end + 1), a   ; loop ends when PORT_Y == start+8
        ld      a, (_draw_y)            ; A = PORT_Y (preserved across LDI)
draw_tile_row:
        out     (#0x89), a
        inc     a
draw_dest_patch:
        ld      de, #0                  ; dest column base (patched by setup)
        ldi                             ; BC is scratch here (decremented, unused);
        ldi                             ; the loop ends via the PORT_Y compare below
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
draw_tile_unkeyed_end:
        cp      #0                      ; patched: start + 8
        jr      nz, draw_tile_row
        call    end_vram_write
        ld      a, (_draw_saved_win1)   ; restore WIN1 (C code lives there)
        out     (#0xA2), a
        ret
        .endif

; --- Keyed rows: B = transparent key, C = PORT_Y (also the loop counter, via a
;     compare against start+8). No per-row memory access; the inner compare/skip
;     is the inherent cost of a runtime colour key (the asset-format #58 path is
;     the separate, faster option). ---
draw_tile_keyed_rows:
        ld      a, (_color_key_value)
        ld      b, a                    ; B = key
        ld      a, (_draw_y)
        ld      c, a                    ; C = PORT_Y
        add     a, #8
        ld      (draw_tile_keyed_end + 1), a   ; loop ends when PORT_Y == start+8
draw_tile_keyed_row:
        ld      a, c
        out     (#0x89), a              ; PORT_Y
        inc     c
draw_tile_keyed_dest_patch:
        ld      de, #0                  ; dest column base (patched by setup)
        ld      a, (hl)
        cp      b
        jr      z, 1$
        ld      (de), a
1$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 2$
        ld      (de), a
2$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 3$
        ld      (de), a
3$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 4$
        ld      (de), a
4$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 5$
        ld      (de), a
5$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 6$
        ld      (de), a
6$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 7$
        ld      (de), a
7$:
        inc     hl
        inc     de
        ld      a, (hl)
        cp      b
        jr      z, 8$
        ld      (de), a
8$:
        inc     hl
        ld      a, c
draw_tile_keyed_end:
        cp      #0                      ; patched: start + 8
        jr      nz, draw_tile_keyed_row
        call    end_vram_write
        ld      a, (_draw_saved_win1)
        out     (#0xA2), a
        ret

_draw_image::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (_draw_image_base_x), a
        inc     hl
        ld      a, (hl)
        ld      (_draw_image_base_y), a
        inc     hl
        ld      a, (hl)                 ; image id
        call    select_image_a

        ld      a, (_image_selected)
        or      a
        ret     z

        ld      hl, #0
        ld      (_draw_image_tile), hl
        ld      a, (_image_height_tiles)
        ld      (_draw_image_rows), a
        ld      a, (_draw_image_base_y)
        ld      (_draw_image_y), a
draw_image_row:
        ld      a, (_image_width_tiles)
        ld      (_draw_image_cols), a
        ld      a, (_draw_image_base_x)
        ld      (_draw_image_x), a
draw_image_col:
        ld      a, (_draw_image_x)
        ld      c, a
        ld      a, (_draw_image_y)
        ld      b, a
        ld      de, (_draw_image_tile)
        call    draw_tile_core

        ld      hl, (_draw_image_tile)
        inc     hl
        ld      (_draw_image_tile), hl
        ld      a, (_draw_image_x)
        inc     a
        ld      (_draw_image_x), a
        ld      a, (_draw_image_cols)
        dec     a
        ld      (_draw_image_cols), a
        jr      nz, draw_image_col

        ld      a, (_draw_image_y)
        inc     a
        ld      (_draw_image_y), a
        ld      a, (_draw_image_rows)
        dec     a
        ld      (_draw_image_rows), a
        jr      nz, draw_image_row
        ret

; =========================================================================
;  Dual-buffer background sync (EvoSDK tileUpdateMap equivalent).
;  EvoSDK games draw PARTIAL tile updates and expect them to persist across
;  the double-buffer flip. draw_tile draws to the back buffer only, so without
;  syncing the two buffers diverge (score/field/title flicker). We track every
;  changed 8x8 cell in a bitmap; after the flip, swap_screen calls
;  _sync_tiles_to_shadow, which copies each dirty cell from the just-shown
;  buffer's clean background (DRAM mirror, read via page #50) into the new
;  hidden buffer. Sprites are page-#5C (VRAM-only) so they never enter the
;  mirror -- the copy is clean background.
; =========================================================================

; mark_tile_dirty: set the dirty bit for cell (C = x tile, B = y tile).
;   Preserves AF/BC/DE/HL (called from inside draw_tile_setup).
mark_tile_dirty:
        push    hl
        push    de
        push    bc
        push    af
        ; offset = y * TILE_DIRTY_STRIDE + (x >> 3)   (max 24*5+4 = 124)
        ld      a, b                    ; y
        add     a, a
        add     a, a
        add     a, b                    ; y*5
        ld      e, a
        ld      a, c                    ; x
        srl     a
        srl     a
        srl     a                       ; x>>3
        add     a, e
        ld      e, a
        ld      d, #0
        ld      hl, #_tile_dirty
        add     hl, de
        ; mask = 1 << (x & 7)
        ld      a, c
        and     #7
        ld      b, a
        inc     b
        xor     a
        scf
1$:
        rla
        djnz    1$                      ; A = 1 << (x&7)
        or      (hl)
        ld      (hl), a
        ld      a, #1
        ld      (_tile_dirty_any), a
        pop     af
        pop     bc
        pop     de
        pop     hl
        ret

; _sync_tiles_to_shadow: copy every dirty 8x8 cell from the visible buffer's
;   mirror to the hidden buffer (page #50). Called by swap_screen AFTER the flip
;   and AFTER the sprite restore. Phase 1 = DI.
_sync_tiles_to_shadow::
        ; Only sync while sprites are active (mirrors EvoSDK: updateTilesFromBuffer
        ; runs inside `if spritesActive`). When sprites are stopped the game gets
        ; raw double buffering, so intentional flip-based effects (e.g. the
        ; level-end picture/field flash) keep working.
        ld      a, (_sprites_active)
        or      a
        ret     z
        ld      a, (_tile_dirty_any)
        or      a
        ret     z
        di
        in      a, (#0xE2)
        ld      (_sync_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a

        ; visible base / hidden base from RGMOD.0
        in      a, (#0xC9)
        and     #1
        ld      hl, #VRAM_BUF0_BASE      ; visible 0
        ld      de, #VRAM_BUF1_BASE      ; hidden 1
        jr      z, sync_bases_ok
        ex      de, hl                  ; visible 1 / hidden 0
sync_bases_ok:
        ld      (_sync_vis_base), hl
        ld      (_sync_dst_base), de

        ld      hl, #_tile_dirty        ; bitmap walk
        xor     a
        ld      (_sync_ty), a
sync_row:
        ld      b, #TILE_DIRTY_STRIDE   ; 5 bytes / row
        xor     a
        ld      (_sync_basex), a
sync_byte:
        ld      a, (hl)
        or      a
        jr      z, sync_byte_next
        push    hl
        push    bc
        ld      c, (hl)                 ; C = 8 dirty bits
        ld      a, (_sync_basex)
        ld      (_sync_x), a
        ld      b, #8
sync_bit:
        rr      c
        jr      nc, sync_bit_next
        push    bc
        .if SAMPLE_ASYNC
        di                              ; DI only around the accel cell-copy; the
        .endif                          ; bitmap walk between cells runs with IRQs on
        call    sync_one_cell           ; (HL/BC preserved by the IM2 handlers) so the
        .if SAMPLE_ASYNC                ; CBL refill IRQ is never starved by a long DI
        ei
        .endif
        pop     bc
sync_bit_next:
        ld      a, (_sync_x)
        inc     a
        ld      (_sync_x), a
        djnz    sync_bit
        pop     bc
        pop     hl
sync_byte_next:
        inc     hl
        ld      a, (_sync_basex)
        add     a, #8
        ld      (_sync_basex), a
        djnz    sync_byte
        ld      a, (_sync_ty)
        inc     a
        ld      (_sync_ty), a
        cp      #TILE_DIRTY_ROWS
        jr      nz, sync_row

        xor     a
        ld      (_tile_dirty_any), a
        ; clear the bitmap for the next frame
        ld      hl, #_tile_dirty
        ld      de, #_tile_dirty + 1
        ld      bc, #TILE_DIRTY_ROWS * TILE_DIRTY_STRIDE - 1
        ld      (hl), #0
        ldir

        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_sync_saved_win3)
        out     (#0xE2), a
        ei                              ; re-enable IM2 (sound); accel block done
        ret

; sync_one_cell: copy the 8x8 cell at (_sync_x, _sync_ty) from the visible
;   buffer (mirror) to the hidden buffer via the accelerator. WIN3 = #50.
sync_one_cell:
        ld      a, (_sync_x)            ; HL = x*8 (16-bit), computed ONCE
        ld      l, a
        ld      h, #0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      b, h
        ld      c, l                    ; BC = x*8 (scratch; B/C reloaded below)
        ld      de, (_sync_dst_base)
        add     hl, de                  ; HL = dst column = hidden base + x*8
        ex      de, hl                  ; DE = dst column
        ld      h, b
        ld      l, c                    ; HL = x*8
        ld      bc, (_sync_vis_base)
        add     hl, bc                  ; HL = src column = visible base + x*8
        ld      a, (_sync_ty)           ; PORT_Y = ty*8 + 28
        add     a, a
        add     a, a
        add     a, a
        add     a, #VRAM_Y_OFFSET
        ld      b, a                    ; B = PORT_Y
        .if UNROLL
        ; --- 8 rows unrolled: HL=src col, DE=dst col (both constant), B=PORT_Y++.
        ;     Drops the per-row `dec c / jr nz`, shortening the DI window that
        ;     _sync_tiles_to_shadow holds across all dirty cells (HW_NOTES §4). ---
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        inc     b
        ld      a, b
        out     (#0x89), a
        ld      d, d
        ld      a, #8
        ld      l, l
        ld      a, (hl)
        ld      (de), a
        ld      b, b
        ret
        .else
        ld      c, #8                   ; 8 rows
sync_cell_row:
        ld      a, b
        out     (#0x89), a
        ld      d, d                    ; accel: set block size
        ld      a, #8
        ld      l, l                    ; accel: copy row (mirror -> VRAM)
        ld      a, (hl)
        ld      (de), a
        ld      b, b                    ; accel: off
        inc     b                       ; next scanline
        dec     c
        jr      nz, sync_cell_row
        ret
        .endif

        .area   _SDKDATA
_tile_dirty_any:
        .db     0
_sync_saved_win3:
        .db     0
_sync_ty:
        .db     0
_sync_basex:
        .db     0
_sync_x:
        .db     0
_sync_vis_base:
        .dw     0
_sync_dst_base:
        .dw     0
_tile_dirty:
        .ds     TILE_DIRTY_ROWS * TILE_DIRTY_STRIDE
_image_base_tile:
        .dw     0
_image_width_tiles:
        .db     0
_image_height_tiles:
        .db     0
_image_selected:
        .db     0
_image_hw_keyed:
        .db     0
_color_key_value:
        .db     0
_draw_src:
        .dw     0
_draw_gfx_page:
        .db     0
_draw_saved_win1:
        .db     0
_draw_y:
        .db     0
_draw_image_base_x:
        .db     0
_draw_image_base_y:
        .db     0
_draw_image_x:
        .db     0
_draw_image_y:
        .db     0
_draw_image_cols:
        .db     0
_draw_image_rows:
        .db     0
_draw_image_tile:
        .dw     0
