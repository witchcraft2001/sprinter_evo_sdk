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
.if NATIVE
        .globl  _joystick_ex            ; NATIVE: full Sega 3/6-button read (u16)
.endif

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

        ; --- Sega/Kempston joystick: read port #07 from SRAM cache, toggle SEL ---
        ; Two facts (verified on HW, see manual_issues.md / sp2000.pdf §9):
        ;  (1) PORT. The Kempston input is decoded WITHOUT address bits A3/A4
        ;      (DCP index = A2,A5,A6,A7,A13-15), so #07 and #1F are the same external
        ;      port. But #1F (range #10-#1F) is ALSO the Z84C15 internal PIO; code
        ;      running in SRAM cache (WIN0) reads that internal port at #1F, so from
        ;      cache the joystick is reached via the #07 alias. (Outside cache, #1F.)
        ;  (2) SEL. An active Sega gamepad refreshes its status only on a SEL edge --
        ;      a single static read returns stale data. SEL = SIO chB WR5 bit7 (DTR),
        ;      port #1B. Directions are reliable at cycle 3 of High/Low/High (cycle 1
        ;      is stale on 8BitDo M30 etc.). Ported from sprinterJoySegaLib.asm/SJTEST
        ;      (TMNT); SEGA_JOY_DELAY (4 NOP @3.5MHz) rescaled for 21MHz.
        ;  (3) POLARITY. The gamepad's lines are active-LOW at the connector (pressed
        ;      pulls the line to 0), but the Sprinter Kempston interface INVERTS them,
        ;      so the port reads active-HIGH: a pressed key = 1. (Confirmed by the
        ;      6-button detect in sprinterJoySegaLib: a grounded/pressed line reads as
        ;      1 -- cycle 6 == %xxxx1111.) So we mask directly, NO cpl, matching the
        ;      EvoSDK joystick() contract (set bit = pressed), like the cursor path above.
        call    sega_sel_high           ; cycle 1 (stale on some pads)
        call    sega_sel_low            ; cycle 2 (A/Start mode)
        call    sega_sel_high           ; cycle 3 -> reliable C,B,Up,Down,Left,Right
        in      a, (#0x07)              ; DB 07 (A=#E0 -> #E007), like SJTEST /cache /07
        and     #0x1F                   ; R=1 L=2 D=4 U=8 FIRE(B)=16 (pressed = 1)
        ld      l, a
        ret

; SEL line = SIO channel B Write Register 5 bit7 (DTR). High=#E0, Low=#60 (both
; keep Tx 8bit/char in D6,D5, as the reference driver does).
sega_sel_high:
        ld      a, #5
        out     (#0x1B), a              ; SIO chB -> point at WR5
        ld      a, #0xE0                ; DTR=1 -> SEL high (normal button set)
        out     (#0x1B), a
        jr      sega_settle
sega_sel_low:
        ld      a, #5
        out     (#0x1B), a
        ld      a, #0x60                ; DTR=0 -> SEL low
        out     (#0x1B), a
sega_settle:
        ; gamepad mux settle. Ref: 4 NOP @3.5MHz (~4.6us). 21MHz is ~6x faster, so
        ; djnz b=8 (~8*13 cyc / 21MHz ~= 5us) matches/exceeds the reference window.
        ld      b, #8
sega_settle_loop:
        djnz    sega_settle_loop
        ret

.if NATIVE
; -------------------------------------------------------------------------
; u16 joystick_ex(void)  [NATIVE only] -- full Sega 3/6-button gamepad read.
; Returns HL:
;   L (low)  = Start,A,C,B,Up,Down,Left,Right   (bit7..bit0)
;   H (high) = Conn,--,Home,Star,Z,Y,X,Mode      (bit7..bit0)
; i.e. JOY_RIGHT/LEFT/DOWN/UP/FIRE(B)/C/A/START in L and JOY_MODE/X/Y/Z/STAR/
; HOME/CONNECTED in H (see evo.h). Direct port of SJTEST.ASM SegaJoyHandler:
; 9 SEL half-cycles (High/Low...), directions from cycle 3, extra buttons from
; cycles 6-8; a 6-button pad is detected when cycle 6 reads %xxxx1111. Reads via
; #07 (SRAM-cache alias of the Kempston port). Registers C,D,E,H,L survive the
; sega_sel_* calls (they only clobber A,B); cycle 9 is bracketed by push/pop.
; -------------------------------------------------------------------------
_joystick_ex::
        call    sega_sel_high           ; cycle 1 (stale)
        in      a, (#0x07)
        call    sega_sel_low            ; cycle 2 -> A/Start + connected bit
        in      a, (#0x07)
        and     #0x3F
        ld      h, a                    ; H = cycle 2
        call    sega_sel_high           ; cycle 3 -> reliable C,B,Up,Down,Left,Right
        in      a, (#0x07)
        and     #0x3F
        ld      l, a                    ; L = cycle 3
        call    sega_sel_low            ; cycle 4
        call    sega_sel_high           ; cycle 5
        call    sega_sel_low            ; cycle 6
        in      a, (#0x07)
        and     #0x3F
        ld      d, a                    ; D = cycle 6 (== %xxxx1111 on a 6-button pad)
        call    sega_sel_high           ; cycle 7 -> Z,Y,X,Mode
        in      a, (#0x07)
        and     #0x3F
        ld      c, a                    ; C = cycle 7
        call    sega_sel_low            ; cycle 8 -> Home,Star
        in      a, (#0x07)
        and     #0x3F
        ld      b, a                    ; B = cycle 8
        push    bc                      ; preserve cycle 7/8 across cycle 9
        call    sega_sel_high           ; cycle 9 -> back to normal (counter reset idle)
        pop     bc

        ld      a, d                    ; 6-button if cycle 6 low nibble == #F
        or      #0xF0
        inc     a
        jr      z, joyex_ext
        ld      bc, #0                  ; 3-button: no extra buttons
        jr      joyex_pack
joyex_ext:
        ld      a, c                    ; C = ----,Z,Y,X,Mode
        and     #0x0F
        ld      c, a
        ld      a, b                    ; cycle 8: Home(bit3), Star(bit1)
        and     #0x0A
        ld      b, a
        and     #0x02                   ; Star
        add     a, b
        rlca
        rlca                            ; Home->bit5, Star->bit4
        or      c
        ld      c, a                    ; C = --,Home,Star,Z,Y,X,Mode
joyex_pack:
        ; H = cycle 2 (used twice), C = extra-button byte so far, L = cycle 3.
        ld      a, h                    ; cycle 2 bit0 = gamepad-connected
        and     #0x01
        rrca                            ; -> bit7
        or      c
        ld      c, a                    ; C = PACK_C (Conn,--,Home,Star,Z,Y,X,Mode)
        ld      a, h                    ; cycle 2 bits 5,4 = Start,A
        and     #0x30
        rlca
        rlca                            ; -> bits 7,6
        or      l                       ; | cycle 3 (C,B,Up,Down,Left,Right)
        ld      l, a                    ; L = PACK_A (Start,A,C,B,Up,Down,Left,Right)
        ld      h, c                    ; H = PACK_C
        ret
.endif

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
