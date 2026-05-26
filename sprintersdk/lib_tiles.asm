; =========================================================================
;  lib_tiles.asm -- tile / image output (EvoSDK responsibility zone)
; =========================================================================
;  Public API: select_image, color_key, draw_tile, draw_tile_key, draw_image.
;  Mirrors evosdk/lib_tiles.asm. Shared screen/asset helpers live in
;  lib_startup.asm and are imported via .globl.
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
        .globl  find_asset_record
        .globl  _asset_found_record

        .area   _CODE

_select_image::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; image id
        ld      a, #1                   ; EVOS type 1 = IMG
        call    find_asset_record
        ret     c
        ld      (_image_payload_ptr), hl

        ld      hl, (_asset_found_record)
        inc     hl
        inc     hl                      ; record.width
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        ld      a, e
        ld      (_image_width_tiles), a

        inc     hl                      ; record.height
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        ld      a, e
        ld      (_image_height_tiles), a
        ret

_color_key::
        ret

_draw_tile_key::
        ; TODO(hw-keyed-tile): route keyed-capable images through VRAM #58
        ; after assetpack marks color_key.N records. Until then, keep the
        ; unkeyed path instead of guessing transparency in C.
        jp      _draw_tile

_draw_tile::
        ld      hl, (_image_payload_ptr)
        ld      a, h
        or      l
        ret     z

        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; x in 8px tiles
        add     a, a
        add     a, a
        add     a, a
        ld      c, a
        ld      b, #0
        inc     hl
        ld      a, (hl)                 ; y in 8px tiles
        add     a, a
        add     a, a
        add     a, a
        ld      (_draw_y), a
        inc     hl
        ld      e, (hl)                 ; tile low
        inc     hl
        ld      d, (hl)                 ; tile high

        ld      hl, #0xC000
        in      a, (#0xC9)              ; draw to hidden buffer = !visible
        and     #1
        xor     #1
        jr      z, 1$
        ld      hl, #0xC140
1$:
        add     hl, bc
        ld      (_draw_dest), hl

        ld      h, d
        ld      l, e
        add     hl, hl                  ; tile * 64
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      de, (_image_payload_ptr)
        add     hl, de                  ; HL = tile payload

        call    begin_vram_write
        ld      a, #8
        ld      (_draw_rows), a
draw_tile_row:
        ld      a, (_draw_y)
        out     (#0x89), a
        inc     a
        ld      (_draw_y), a

        ld      de, (_draw_dest)
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
        jp      end_vram_write

_draw_image::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (_draw_image_base_x), a
        inc     hl
        ld      a, (hl)
        ld      (_draw_image_base_y), a
        inc     hl
        ld      c, (hl)                 ; image id
        ld      h, #0
        ld      l, c
        push    hl
        call    _select_image
        pop     hl

        ld      hl, (_image_payload_ptr)
        ld      a, h
        or      l
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
        ld      hl, (_draw_image_tile)
        push    hl
        ld      a, (_draw_image_y)
        ld      h, a
        ld      a, (_draw_image_x)
        ld      l, a
        push    hl
        call    _draw_tile
        pop     hl
        pop     hl

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

        .area   _DATA
_image_payload_ptr:
        .dw     0
_image_width_tiles:
        .db     0
_image_height_tiles:
        .db     0
_draw_dest:
        .dw     0
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
