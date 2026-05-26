; =========================================================================
;  lib_sprites.asm -- sprite engine (EvoSDK responsibility zone)
; =========================================================================
;  Public API: set_sprite, sprites_start, sprites_stop.
;  Mirrors evosdk/lib_sprites.asm. Stubs until the sprite engine is ported
;  (Этап 4: 64x 16x16 sprites, hw transparency via VRAM #5C/#58, bg restore).
; =========================================================================

        .module lib_sprites

        .globl  _set_sprite
        .globl  _sprites_start
        .globl  _sprites_stop

        .area   _SDK

_set_sprite::
_sprites_start::
_sprites_stop::
        ret
