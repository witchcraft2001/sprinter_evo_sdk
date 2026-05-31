; =========================================================================
;  lib_input.asm -- joystick / keyboard / mouse (EvoSDK responsibility zone)
; =========================================================================
;  Public API: joystick, keyboard, mouse_pos/set/clip/delta.
;  Mirrors evosdk/lib_input.asm. joystick() = cursor keys (Caps + 5/6/7/8) +
;  Space, falling back to Kempston; keyboard() is the separate ZX matrix API.
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

; mouse_pos(u8* x, u8* y) -> buttons. Returns the cached pointer position
; (X already in 2-pixel units, like sprites). Mirrors evosdk/evo.c semantics.
_mouse_pos::
        call    mouse_poll_once
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)
        inc     hl
        ld      b, (hl)
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      a, (_mouse_x)
        ld      (bc), a
        ld      a, (_mouse_y)
        ld      (de), a
        ld      a, (_mouse_btn)
        ld      l, a
        ret

; mouse_delta(i8* x, i8* y) -> buttons. Raw per-frame movement (X at full
; resolution). evosdk/evo.c wrote *y to the wrong pointer; here it is correct.
_mouse_delta::
        call    mouse_poll_once
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)
        inc     hl
        ld      b, (hl)
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      a, (_mouse_dx)
        ld      (bc), a
        ld      a, (_mouse_dy)
        ld      (de), a
        ld      a, (_mouse_btn)
        ld      l, a
        ret

; joystick(): cursor keys (Sinclair: Caps + 5/6/7/8) + Space fire, else Kempston.
; Mirrors evosdk/lib_input.asm (evo.h contract "kempston + cursor keys with space"),
; with ONE Sprinter-specific rule: Space is read as fire ONLY when Caps is NOT held.
; On Sprinter Caps+Space is the Esc combo, and games (e.g. game_xnx input_fire_pressed)
; rely on joystick() NOT reporting fire for it (anti-misclick). When Caps IS held the
; Sinclair cursor is active and fire comes from key 0. Bits: RIGHT=1 LEFT=2 DOWN=4 UP=8 FIRE=16.
; (Arrow-key -> ZX-matrix mapping to be confirmed on HW, plan Этап 6.)
_joystick::
        ld      l, #0

        ld      bc, #0xFEFE             ; row Caps,Z,X,C,V
        in      a, (c)
        rra                             ; CF = Caps (CF=1 -> Caps not held)
        jr      c, joy_space            ; Caps not held -> Space = fire
        ; --- Caps held: Sinclair cursor (5/6/7/8 + key 0 fire); Space NOT read
        ;     here (Caps+Space = Esc on Sprinter) ---
        ld      b, #0xF7                ; row 1,2,3,4,5
        in      a, (c)
        and     #0x10                   ; bit4 = key 5
        jr      nz, 1$
        set     1, l                    ; JOY_LEFT  (key 5)
1$:
        ld      b, #0xEF                ; row 0,9,8,7,6
        in      a, (c)
        rra                             ; bit0 = key 0
        jr      c, 2$
        set     4, l                    ; JOY_FIRE  (key 0)
2$:
        rra                             ; bit1 = key 9 (ignored)
        rra                             ; bit2 = key 8
        jr      c, 3$
        set     0, l                    ; JOY_RIGHT (key 8)
3$:
        rra                             ; bit3 = key 7
        jr      c, 4$
        set     3, l                    ; JOY_UP    (key 7)
4$:
        rra                             ; bit4 = key 6
        jr      c, 5$
        set     2, l                    ; JOY_DOWN  (key 6)
5$:
        jr      joy_check               ; Caps held -> skip Space-fire
joy_space:
        ld      b, #0x7F                ; row Space,Sym,M,N,B
        in      a, (c)
        rra                             ; bit0 = Space
        jr      c, joy_check
        set     4, l                    ; JOY_FIRE  (Space, only when Caps not held)
joy_check:
        ld      a, l
        or      a
        ret     nz                      ; any cursor/space key -> return it

        ld      bc, #0x001F             ; else Kempston-compatible joystick
        in      a, (c)
        and     #0x1F
        ld      l, a
        ret

; mouse_set(u8 x, u8 y): set pointer position, then re-clip.
_mouse_set::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (_mouse_x), a
        inc     hl
        ld      a, (hl)
        ld      (_mouse_y), a
        jp      mouse_apply_clip

; mouse_clip(u8 xmin, u8 ymin, u8 xmax, u8 ymax): set clip zone, then re-clip.
_mouse_clip::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (_mouse_cx1), a
        inc     hl
        ld      a, (hl)
        ld      (_mouse_cy1), a
        inc     hl
        ld      a, (hl)
        ld      (_mouse_cx2), a
        inc     hl
        ld      a, (hl)
        ld      (_mouse_cy2), a
        jp      mouse_apply_clip

; -------------------------------------------------------------------------
; Kempston mouse (ports #FBDF=x, #FFDF=y, #FADF=buttons). Polled at most once
; per frame (gated by the frame counter) so mouse_pos and mouse_delta stay
; consistent within a frame without an IM2 hook. X accumulates dx/2 (2-pixel
; units, like sprites); Y accumulates dy. Mirrors evosdk poll_mouse.
; ⚠ Sprinter Kempston-mouse port support to be confirmed on HW (plan Этап 6).
; -------------------------------------------------------------------------
mouse_poll_once:
        ld      a, (_time_counter)      ; frame low byte
        ld      hl, #_mouse_last_poll
        cp      (hl)
        ret     z                       ; already polled this frame
        ld      (hl), a

        ld      bc, #0xFBDF             ; X counter
        in      a, (c)
        ld      e, a
        ld      a, (_mouse_prev_dx)
        ld      d, a
        ld      a, e
        ld      (_mouse_prev_dx), a
        sub     d                        ; dx = cur - prev
        ld      (_mouse_dx), a
        ld      b, #0xFF                ; Y counter (#FFDF)
        in      a, (c)
        ld      e, a
        ld      a, (_mouse_prev_dy)
        ld      d, a
        ld      a, e
        ld      (_mouse_prev_dy), a
        sub     d
        ld      (_mouse_dy), a
        ld      b, #0xFA                ; buttons (#FADF)
        in      a, (c)
        cpl
        and     #7
        ld      (_mouse_btn), a

        ; X += dx/2 (signed), clamp [cx1, cx2]
        ld      a, (_mouse_dx)
        sra     a                        ; dx>>1, sign preserved
        ld      e, a
        add     a, a
        sbc     a, a                     ; A = 0x00/0xFF sign extension
        ld      d, a                     ; DE = signed delta
        ld      a, (_mouse_x)
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (_mouse_cx1)
        ld      b, a
        ld      a, (_mouse_cx2)
        ld      c, a
        call    clamp_hl_signed
        ld      (_mouse_x), a

        ; Y += dy (signed), clamp [cy1, cy2]
        ld      a, (_mouse_dy)
        ld      e, a
        add     a, a
        sbc     a, a
        ld      d, a
        ld      a, (_mouse_y)
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (_mouse_cy1)
        ld      b, a
        ld      a, (_mouse_cy2)
        ld      c, a
        call    clamp_hl_signed
        ld      (_mouse_y), a
        ret

; mouse_apply_clip: clamp cached X/Y into the clip zone (both already bytes).
mouse_apply_clip:
        ld      a, (_mouse_cx1)
        ld      b, a
        ld      a, (_mouse_cx2)
        ld      c, a
        ld      a, (_mouse_x)
        call    clamp_byte
        ld      (_mouse_x), a
        ld      a, (_mouse_cy1)
        ld      b, a
        ld      a, (_mouse_cy2)
        ld      c, a
        ld      a, (_mouse_y)
        call    clamp_byte
        ld      (_mouse_y), a
        ret

; clamp_byte: A clamped to [B=lo, C=hi] (unsigned, lo<=hi). Returns A.
clamp_byte:
        cp      b
        jr      nc, 1$
        ld      a, b
1$:
        cp      c
        jr      c, 2$
        jr      z, 2$
        ld      a, c
2$:
        ret

; clamp_hl_signed: signed 16-bit HL clamped to [B=lo, C=hi] (lo,hi 0..255).
; Returns the clamped byte in A.
clamp_hl_signed:
        bit     7, h
        jr      nz, 3$                   ; HL negative -> lo
        ld      a, h
        or      a
        jr      nz, 4$                   ; HL > 255 -> hi
        ld      a, l
        cp      b
        jr      c, 3$                    ; L < lo
        ld      a, c
        cp      l
        jr      c, 4$                    ; hi < L -> hi
        ld      a, l
        ret
3$:
        ld      a, b
        ret
4$:
        ld      a, c
        ret

        .area   _SDKDATA
_kb_prev_state:
        .ds     40
_mouse_x:
        .db     80
_mouse_y:
        .db     100
_mouse_dx:
        .db     0
_mouse_dy:
        .db     0
_mouse_prev_dx:
        .db     0
_mouse_prev_dy:
        .db     0
_mouse_btn:
        .db     0
_mouse_cx1:
        .db     0
_mouse_cx2:
        .db     160
_mouse_cy1:
        .db     0
_mouse_cy2:
        .db     200
_mouse_last_poll:
        .db     0xFF                    ; != any frame low byte -> first call polls
