; =========================================================================
;  lib_input.asm -- joystick / keyboard / mouse (EvoSDK responsibility zone)
; =========================================================================
;  Public API: joystick, keyboard, mouse_pos/set/clip/delta.
;  Mirrors evosdk/lib_input.asm. Фаза 1 plan (HW_NOTES §8): ZX-matrix #FE
;  keyboard (калька), Kempston joystick #1F, Kempston mouse. Currently stubs
;  (keyboard zeroes the 40-byte array, mouse/joystick return idle) until the
;  input port reads are wired (Этап 6).
; =========================================================================

        .module lib_input

        .globl  _joystick
        .globl  _keyboard
        .globl  _mouse_pos
        .globl  _mouse_set
        .globl  _mouse_clip
        .globl  _mouse_delta

        .area   _CODE

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
        ret
