; =========================================================================
;  lib_startup.asm -- minimal Sprinter EvoSDK runtime bootstrap (Stage 2)
; =========================================================================
;  This file keeps the EvoSDK public entry names while the platform-specific
;  libraries are being ported. Hot graphics/sound paths are intentionally left
;  as asm entry points here and will move into their matching lib_*.asm files.
; =========================================================================

        .module lib_startup

        .globl  _evo_runtime_init
        .globl  _evo_runtime_shutdown

        .globl  _memset
        .globl  _memcpy
        .globl  _rand16
        .globl  _border
        .globl  _vsync
        .globl  _joystick
        .globl  _keyboard
        .globl  _mouse_pos
        .globl  _mouse_set
        .globl  _mouse_clip
        .globl  _mouse_delta
        .globl  _sfx_play
        .globl  _sfx_stop
        .globl  _music_play
        .globl  _music_stop
        .globl  _sample_play
        .globl  _pal_clear
        .globl  _pal_bright
        .globl  _pal_select
        .globl  _pal_copy
        .globl  _pal_col
        .globl  _pal_custom
        .globl  _select_image
        .globl  _color_key
        .globl  _draw_tile
        .globl  _draw_tile_key
        .globl  _draw_image
        .globl  _clear_screen
        .globl  _swap_screen
        .globl  _sprites_start
        .globl  _sprites_stop
        .globl  _set_sprite
        .globl  _time
        .globl  _delay

        .area   _CODE

_evo_runtime_init::
        di
        call    save_dss_state

        ; DSS SetVMod #50: A=0x81 (320x256x8bpp), B=page.
        ; Source: evosdk_libs/sprinter/lib/video_setmode.s and flappybird
        ; sequence. Both pages must be initialized before any RGMOD switch:
        ; initializing only the current page leaves the other page black.
        push    ix
        ld      a, #0x81
        ld      b, #1
        call    setvmod_page
        ld      a, #0x81
        ld      b, #0
        call    setvmod_page
        pop     ix

        xor     a
        out     (#0xC9), a             ; visible screen A, blank bit clear
        ld      (_screen_active), a
        call    _pal_clear
        ei
        ret

_evo_runtime_shutdown::
        di
        call    restore_dss_state
        ei
        ret

setvmod_page:
        ld      c, #0x50                ; DSS SetVMod
        rst     #0x10
        ret

save_dss_state:
        in      a, (#0x82)
        ld      (_dss_win0_page), a
        in      a, (#0xA2)
        ld      (_dss_win1_page), a
        in      a, (#0xC2)
        ld      (_dss_win2_page), a
        in      a, (#0xE2)
        ld      (_dss_win3_page), a
        ; NB: PORT_Y (#89) is write-only -- IN returns CBL state, not PORT_Y
        ; (HW_NOTES §3). Nothing to save; restore_dss_state parks it at #C0.
        push    ix
        ld      c, #0x51                ; DSS GetVMod -> A
        rst     #0x10
        pop     ix
        ld      (_dss_video_mode), a
        ret

restore_dss_state:
        push    ix
        ld      a, (_dss_video_mode)
        bit     7, a
        jr      nz, 1$
        ld      bc, #0x004E             ; CBL control: reset before text mode
        xor     a
        out     (c), a
        ld      a, (_dss_video_mode)
1$:
        ld      b, #0
        ld      c, #0x50                ; DSS SetVMod
        rst     #0x10
        pop     ix

        ld      a, (_dss_win0_page)
        out     (#0x82), a
        ld      a, (_dss_win1_page)
        out     (#0xA2), a
        ld      a, (_dss_win2_page)
        out     (#0xC2), a
        ld      a, (_dss_win3_page)
        out     (#0xE2), a
        ld      a, #0xC0                ; safe PORT_Y value between programs
        out     (#0x89), a
        ret

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

_pal_clear::
        ; Direct palette protocol from HW_NOTES.md §3:
        ; WIN3=#50, PORT_Y=index, #C3E0/#C3E1/#C3E2 = R/G/B.
        in      a, (#0xE2)
        ld      d, a
        ld      a, #0x50
        out     (#0xE2), a
        ld      b, #0
        xor     a
1$:
        ld      a, b
        out     (#0x89), a
        xor     a
        ld      (#0xC3E0), a
        ld      (#0xC3E1), a
        ld      (#0xC3E2), a
        djnz    1$
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, d
        out     (#0xE2), a
        ret

_keyboard::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      h, d
        ld      l, e
        ld      b, #40
        xor     a
1$:
        ld      (hl), a
        inc     hl
        djnz    1$
        ret

_mouse_pos::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)
        inc     hl
        ld      b, (hl)
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        xor     a
        ld      (bc), a
        ld      (de), a
        ld      l, a
        ret

_mouse_delta::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)
        inc     hl
        ld      b, (hl)
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        xor     a
        ld      (bc), a
        ld      (de), a
        ld      l, a
        ret

_joystick::
        ld      l, #0
        ret

_mouse_set::
_mouse_clip::
_sfx_play::
_sfx_stop::
_music_play::
_music_stop::
_sample_play::
_pal_bright::
_pal_select::
_pal_copy::
_pal_col::
_pal_custom::
_select_image::
_color_key::
_draw_tile::
_draw_tile_key::
_draw_image::
_clear_screen::
_sprites_start::
_sprites_stop::
_set_sprite::
        ret

        .area   _DATA
_dss_win0_page:
        .db     0
_dss_win1_page:
        .db     0
_dss_win2_page:
        .db     0
_dss_win3_page:
        .db     0
_dss_video_mode:
        .db     0
_screen_active:
        .db     0
_time_counter:
        .db     0, 0, 0, 0
_rand_seed1:
        .dw     1
_rand_seed2:
        .dw     5
