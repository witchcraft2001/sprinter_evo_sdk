; =========================================================================
;  lib_input.asm -- joystick / keyboard / mouse (EvoSDK responsibility zone)
; =========================================================================
;  Public API: joystick, keyboard, mouse_pos/set/clip/delta.
;  Mirrors evosdk/lib_input.asm. joystick() is Kempston only; keyboard() is
;  the separate ZX matrix API.
; =========================================================================

        .module lib_input

        .globl  _joystick
        .globl  _keyboard
        .globl  _mouse_pos
        .globl  _mouse_set
        .globl  _mouse_clip
        .globl  _mouse_delta

        .area   _SDK

_keyboard::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        push    ix
        ld      h, d
        ld      l, e                    ; HL = user keys[40]
        ld      ix, #_kb_prev_state     ; previous KEY_DOWN state, 0/0xFF

        ld      bc, #0xFEFE             ; CAPS, Z, X, C, V
        call    kb_row
        ld      bc, #0xFDFE             ; A, S, D, F, G
        call    kb_row
        ld      bc, #0xFBFE             ; Q, W, E, R, T
        call    kb_row
        ld      bc, #0xF7FE             ; 1, 2, 3, 4, 5
        call    kb_row
        ld      bc, #0xEFFE             ; 0, 9, 8, 7, 6
        call    kb_row
        ld      bc, #0xDFFE             ; P, O, I, U, Y
        call    kb_row
        ld      bc, #0xBFFE             ; Enter, L, K, J, H
        call    kb_row
        ld      bc, #0x7FFE             ; Space, Symbol Shift, M, N, B
        call    kb_row
        pop     ix
        ret

kb_row:
        in      a, (c)
        cpl                             ; pressed keys become 1 bits
        ld      e, a
        ld      b, #5
1$:
        rr      e                       ; CF = next key down
        sbc     a, a                    ; A = 0xFF if down, 0 otherwise
        ld      c, a                    ; C = current down mask
        xor     0(ix)                   ; changed?
        and     c                       ; newly down only
        and     #2                      ; KEY_PRESS
        ld      0(ix), c
        rr      c                       ; CF = KEY_DOWN
        jr      nc, 2$
        or      #1
2$:
        ld      (hl), a
        inc     ix
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
        ld      bc, #0x001F             ; Kempston-compatible joystick only
        in      a, (c)
        and     #0x1F
        ld      l, a
        ret

_mouse_set::
_mouse_clip::
        ret

        .area   _SDKDATA
_kb_prev_state:
        .ds     40
