        ;; SDCC 2.9.0 z80 multiplication helpers.
        ;; Derived from the historical SDCC z80 runtime.

        .area   _CODE

__mulint_rrx_s::
        ld      hl,#2
        add     hl,sp

        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a

__muluchar_rrx_hds::
__mulint_rrx_hds::
        ld      b,h
        ld      c,l

__mul16::
        ld      hl,#0
        ld      a,b
        ld      b,#16

        or      a
        jr      NZ,1$

        ld      b,#8
        ld      a,c
1$:
        add     hl,hl
        rl      c
        rla
        jr      NC,2$
        add     hl,de
2$:
        djnz    1$
        ret
