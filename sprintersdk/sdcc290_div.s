        ;; SDCC 2.9.0 z80 division helpers.
        ;; Derived from the historical SDCC z80 runtime.

        .area   _CODE

        ;; Unsigned
__divuchar_rrx_s::
        ld      hl,#2+1
        add     hl,sp

        ld      e,(hl)
        dec     hl
        ld      l,(hl)

        ;; Fall through
__divuchar_rrx_hds::
        ld      c,l
        call    __divu8

        ld      l,c
        ld      h,b

        ret

__divuint_rrx_s::
        ld      hl,#2+3
        add     hl,sp

        ld      d,(hl)
        dec     hl
        ld      e,(hl)
        dec     hl
        ld      a,(hl)
        dec     hl
        ld      l,(hl)
        ld      h,a

        ;; Fall through
__divuint_rrx_hds::
        ld      b,h
        ld      c,l
        call    __divu16

        ld      l,c
        ld      h,b

        ret

__divsuchar_rrx_s::
        ld      hl,#2+1
        add     hl,sp

        ld      e,(hl)
        dec     hl
        ld      c,(hl)
        ld      b, #0

        call    signexte

        ld      l,c
        ld      h,b

        ret

__modsuchar_rrx_s::
        ld      hl,#2+1
        add     hl,sp

        ld      e,(hl)
        dec     hl
        ld      c,(hl)
        ld      b, #0

        call    signexte

        ld      l,e
        ld      h,d

        ret

__divuschar_rrx_s::
        ld      hl,#2+1
        add     hl,sp

        ld      e,(hl)
        ld      d, #0
        dec     hl
        ld      c,(hl)

        ld      a,c
        rlca
        sbc     a
        ld      b,a

        call    __div16

        ld      l,c
        ld      h,b

        ret

__div8::
.mod8::
        ld      a,c
        rlca
        sbc     a
        ld      b,a
signexte:
        ld      a,e
        rlca
        sbc     a
        ld      d,a

__div16::
.mod16::
        ld      a,b
        push    af
        xor     d
        push    af

        bit     7,d
        jr      Z,.chkde
        sub     a
        sub     e
        ld      e,a
        sbc     a
        sub     d
        ld      d,a
.chkde:
        bit     7,b
        jr      Z,.dodiv
        sub     a
        sub     c
        ld      c,a
        sbc     a
        sub     b
        ld      b,a
.dodiv:
        call    __divu16
        jr      C,.exit
        pop     af
        and     #0x80
        jr      Z,.dorem
        sub     a
        sub     c
        ld      c,a
        sbc     a
        sub     b
        ld      b,a
.dorem:
        pop     af
        and     #0x80
        ret     Z
        sub     a
        sub     e
        ld      e,a
        sbc     a
        sub     d
        ld      d,a
        ret
.exit:
        pop     af
        pop     af
        ret

__divu8::
.modu8::
        ld      b,#0x00
        ld      d,b

__divu16::
.modu16::
        ld      a,e
        or      d
        jr      NZ,.divide
        ld      bc,#0x00
        ld      d,b
        ld      e,c
        scf
        ret
.divide:
        ld      hl,#0
        or      a
        ex      af,af'
        ld      a,#16
.dvloop:
        ex      af,af'
        rl      c
        rl      b
        adc     hl,hl

        push    hl
        sbc     hl,de
        ccf
        jr      C,.drop
        pop     hl
        jr      .nodrop
.drop:
        inc     sp
        inc     sp
.nodrop:
        ex      af,af'
        dec     a
        jp      NZ,.dvloop
        ex      af,af'
        ld      d,h
        ld      e,l
        rl      c
        rl      b
        or      a
        ret
