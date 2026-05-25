        ;; SDCC 2.9.0 z80 unsigned long division helper.
        ;; Derived from the historical SDCC z80 runtime.

        .module _divulong
        .optsdcc -mz80

        .globl __divulong

        .area _DATA
        .area _OVERLAY
        .area _HOME
        .area _GSINIT
        .area _GSFINAL
        .area _GSINIT
        .area _HOME
        .area _HOME
        .area _CODE

__divulong_start::
__divulong:
        push    ix
        ld      ix,#0
        add     ix,sp
        ld      hl,#-6
        add     hl,sp
        ld      sp,hl

        xor     a,a
        ld      -4 (ix),a
        ld      -3 (ix),a
        ld      -2 (ix),a
        ld      -1 (ix),a
        ld      -5 (ix),#0x20
00105$:
        ld      a,7 (ix)
        rlc     a
        and     a,#0x01
        ld      -6 (ix),a

        ld      a,#0x01
        push    af
        inc     sp
        ld      l,6 (ix)
        ld      h,7 (ix)
        push    hl
        ld      l,4 (ix)
        ld      h,5 (ix)
        push    hl
        call    __rlulong_rrx_s
        pop     af
        pop     af
        inc     sp
        ld      b,h
        ld      4 (ix),l
        ld      5 (ix),b
        ld      6 (ix),e
        ld      7 (ix),d

        ld      a,#0x01
        push    af
        inc     sp
        ld      l,-2 (ix)
        ld      h,-1 (ix)
        push    hl
        ld      l,-4 (ix)
        ld      h,-3 (ix)
        push    hl
        call    __rlulong_rrx_s
        pop     af
        pop     af
        inc     sp
        ld      b,h
        ld      c,l
        ld      -4 (ix),c
        ld      -3 (ix),b
        ld      -2 (ix),e
        ld      -1 (ix),d

        xor     a,a
        or      a,-6 (ix)
        jr      Z,00102$

        ld      a,-4 (ix)
        or      a,#0x01
        ld      -4 (ix),a
00102$:
        ld      a,-4 (ix)
        sub     a,8 (ix)
        ld      a,-3 (ix)
        sbc     a,9 (ix)
        ld      a,-2 (ix)
        sbc     a,10 (ix)
        ld      a,-1 (ix)
        sbc     a,11 (ix)
        jr      C,00106$

        ld      a,-4 (ix)
        sub     a,8 (ix)
        ld      -4 (ix),a
        ld      a,-3 (ix)
        sbc     a,9 (ix)
        ld      -3 (ix),a
        ld      a,-2 (ix)
        sbc     a,10 (ix)
        ld      -2 (ix),a
        ld      a,-1 (ix)
        sbc     a,11 (ix)
        ld      -1 (ix),a

        ld      a,4 (ix)
        or      a,#0x01
        ld      4 (ix),a
00106$:
        dec     -5 (ix)
        xor     a,a
        or      a,-5 (ix)
        jp      NZ,00105$

        ld      l,4 (ix)
        ld      h,5 (ix)
        ld      e,6 (ix)
        ld      d,7 (ix)
        ld      sp,ix
        pop     ix
        ret
__divulong_end::

        .area _CODE
        .area _CABS
