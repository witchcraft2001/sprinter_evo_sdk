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

        ; --- imported from lib_startup.asm ---
        .globl  begin_vram_write
        .globl  end_vram_write
        .globl  _vram_base              ; back buffer base (#C000/#C140)

; --- loader-filled runtime tables in the SDK SRAM region. MUST match loader.asm
;     and lib_startup.asm. ---
EVO_PAGE_TABLE = 0x1A00                 ; phys page numbers, index = logical page
EVO_IMG_TABLE  = 0x1B11                 ; EVO_META(#1B00)+16 hdr +1 img_count byte
                                        ; records: { u16 base_tile, u8 wt, u8 ht }

        .area   _SDK

_select_image::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; image id
select_image_a:
        ; record = EVO_IMG_TABLE + id*4
        ld      l, a
        ld      h, #0
        add     hl, hl
        add     hl, hl                  ; id*4
        ld      de, #EVO_IMG_TABLE
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; de = base_tile (global)
        ld      (_image_base_tile), de
        inc     hl
        ld      a, (hl)                 ; w in tiles
        ld      (_image_width_tiles), a
        inc     hl
        ld      a, (hl)                 ; h in tiles
        ld      (_image_height_tiles), a
        ld      a, #1
        ld      (_image_selected), a
        ret

_color_key::
        ret

_draw_tile_key::
        ; TODO(hw-keyed-tile): route keyed images through VRAM #58 once
        ; assetpack marks color_key.N records. Until then, unkeyed path.
        jp      _draw_tile

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
        ld      l, c
        ld      h, #0
        add     hl, hl
        add     hl, hl
        add     hl, hl                  ; x*8 (0..312), must stay 16-bit
        ld      (draw_dest_x_patch + 1), hl
        ld      a, b
        add     a, a
        add     a, a
        add     a, a                    ; y*8 (pixel row in the 320x200 surface)
        add     a, #28                  ; +28: center surface in the 256-row frame
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

        ld      hl, (_draw_src)         ; persists, advances 8 bytes/row
        ld      a, #8
        ld      (_draw_rows), a
draw_tile_row:
        ld      a, (_draw_y)
        out     (#0x89), a
        inc     a
        ld      (_draw_y), a

draw_dest_patch:
        ld      de, #0
        ld      bc, #8
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi

        ld      a, (_draw_rows)
        dec     a
        ld      (_draw_rows), a
        jr      nz, draw_tile_row

        call    end_vram_write
        ld      a, (_draw_saved_win1)   ; restore WIN1 (C code lives there)
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

        .area   _SDKDATA
_image_base_tile:
        .dw     0
_image_width_tiles:
        .db     0
_image_height_tiles:
        .db     0
_image_selected:
        .db     0
_draw_src:
        .dw     0
_draw_gfx_page:
        .db     0
_draw_saved_win1:
        .db     0
_draw_y:
        .db     0
_draw_rows:
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
