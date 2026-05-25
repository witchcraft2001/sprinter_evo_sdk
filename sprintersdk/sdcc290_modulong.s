        ;; SDCC 2.9.0 z80 unsigned long modulo helper.
        ;; Derived from the historical SDCC z80 runtime.

        .module _modulong
        .optsdcc -mz80

        .globl __modulong

        .area _DATA
        .area _OVERLAY
        .area _HOME
        .area _GSINIT
        .area _GSFINAL
        .area _GSINIT
        .area _HOME
        .area _HOME
        .area _CODE

__modulong_start::
__modulong:
        push    ix
        ld      ix,#0
        add     ix,sp
        push    af

        ld      -2 (ix),#0x00
        ld      -1 (ix),#0x00
00103$:
        ld      a,11 (ix)
        rlc     a
        and     a,#0x01
        jp      NZ,00117$

        ld      a,#0x01
        push    af
        inc     sp
        ld      l,10 (ix)
        ld      h,11 (ix)
        push    hl
        ld      l,8 (ix)
        ld      h,9 (ix)
        push    hl
        call    __rlulong_rrx_s
        pop     af
        pop     af
        inc     sp
        ld      c,d
        ld      b,e
        ld      d,h
        ld      e,l
        ld      8 (ix),e
        ld      9 (ix),d
        ld      10 (ix),b
        ld      11 (ix),c

        ld      a,4 (ix)
        sub     a,8 (ix)
        ld      a,5 (ix)
        sbc     a,9 (ix)
        ld      a,6 (ix)
        sbc     a,10 (ix)
        ld      a,7 (ix)
        sbc     a,11 (ix)
        jr      NC,00102$

        ld      a,#0x01
        push    af
        inc     sp
        ld      l,10 (ix)
        ld      h,11 (ix)
        push    hl
        ld      l,8 (ix)
        ld      h,9 (ix)
        push    hl
        call    __rrulong_rrx_s
        pop     af
        pop     af
        inc     sp
        ld      b,h
        ld      8 (ix),l
        ld      9 (ix),b
        ld      10 (ix),e
        ld      11 (ix),d
        jr      00117$
00102$:
        inc     -1 (ix)
        ld      a,-1 (ix)
        ld      -2 (ix),a
        jp      00103$
00117$:
00108$:
        ld      a,4 (ix)
        sub     a,8 (ix)
        ld      a,5 (ix)
        sbc     a,9 (ix)
        ld      a,6 (ix)
        sbc     a,10 (ix)
        ld      a,7 (ix)
        sbc     a,11 (ix)
        jr      C,00107$

        ld      a,4 (ix)
        sub     a,8 (ix)
        ld      4 (ix),a
        ld      a,5 (ix)
        sbc     a,9 (ix)
        ld      5 (ix),a
        ld      a,6 (ix)
        sbc     a,10 (ix)
        ld      6 (ix),a
        ld      a,7 (ix)
        sbc     a,11 (ix)
        ld      7 (ix),a
00107$:
        ld      a,#0x01
        push    af
        inc     sp
        ld      l,10 (ix)
        ld      h,11 (ix)
        push    hl
        ld      l,8 (ix)
        ld      h,9 (ix)
        push    hl
        call    __rrulong_rrx_s
        pop     af
        pop     af
        inc     sp
        ld      c,d
        ld      d,e
        ld      e,h
        ld      8 (ix),l
        ld      9 (ix),e
        ld      10 (ix),d
        ld      11 (ix),c

        ld      c,-2 (ix)
        dec     -2 (ix)
        xor     a,a
        or      a,c
        jp      NZ,00108$

        ld      l,4 (ix)
        ld      h,5 (ix)
        ld      e,6 (ix)
        ld      d,7 (ix)
        ld      sp,ix
        pop     ix
        ret
__modulong_end::

        .area _CODE
        .area _CABS
