        ;; SDCC 2.9.0 z80 32-bit multiplication helper.
        ;; Signed and unsigned long multiplication are identical modulo 32 bits.

        .module _mullong
        .optsdcc -mz80

        .globl __mullong
        .globl __mullong_rrx_s

        .area _DATA
        .area _OVERLAY
        .area _HOME
        .area _GSINIT
        .area _GSFINAL
        .area _GSINIT
        .area _HOME
        .area _HOME
        .area _CODE

__mullong_start::
__mullong_rrx_s::
__mullong:
        push    ix
        ld      ix,#0
        add     ix,sp
        ld      hl,#-5
        add     hl,sp
        ld      sp,hl

        xor     a,a
        ld      -4 (ix),a
        ld      -3 (ix),a
        ld      -2 (ix),a
        ld      -1 (ix),a
        ld      -5 (ix),#0x20

00101$:
        ld      a,8 (ix)
        and     a,#0x01
        jr      Z,00102$

        ld      a,-4 (ix)
        add     a,4 (ix)
        ld      -4 (ix),a
        ld      a,-3 (ix)
        adc     a,5 (ix)
        ld      -3 (ix),a
        ld      a,-2 (ix)
        adc     a,6 (ix)
        ld      -2 (ix),a
        ld      a,-1 (ix)
        adc     a,7 (ix)
        ld      -1 (ix),a

00102$:
        ld      a,4 (ix)
        add     a,a
        ld      4 (ix),a
        ld      a,5 (ix)
        rla
        ld      5 (ix),a
        ld      a,6 (ix)
        rla
        ld      6 (ix),a
        ld      a,7 (ix)
        rla
        ld      7 (ix),a

        ld      a,11 (ix)
        srl     a
        ld      11 (ix),a
        ld      a,10 (ix)
        rra
        ld      10 (ix),a
        ld      a,9 (ix)
        rra
        ld      9 (ix),a
        ld      a,8 (ix)
        rra
        ld      8 (ix),a

        dec     -5 (ix)
        ld      a,-5 (ix)
        or      a,a
        jr      NZ,00101$

        ld      l,-4 (ix)
        ld      h,-3 (ix)
        ld      e,-2 (ix)
        ld      d,-1 (ix)
        ld      sp,ix
        pop     ix
        ret
__mullong_end::

        .area _CODE
        .area _CABS
