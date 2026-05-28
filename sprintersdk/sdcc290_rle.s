; RLE initializer expander emitted by SDCC 2.9.0 for compressed global data.
; SDCC generates `ld hl,#dest / call __initrleblock` followed by inline RLE
; bytes in _GSINIT; the helper expands them and returns past the inline data.
; The SDK links its own crt0.s without z80.lib, so this routine (otherwise
; pulled from SDCC's crt0_rle.s) must be provided here. Ported 1:1 from
; sdcc-2.9.0/share/sdcc/lib/src/z80/crt0_rle.s.

	.module sdcc290_rle

	.globl __initrleblock

	.area _CODE

	;; Special RLE decoder used for initing global data
__initrleblock::
	;; Pull the destination address out
	ld	c,l
	ld	b,h

	;; Pop the return address
	pop	hl
1$:
	;; Fetch the run
	ld	e,(hl)
	inc	hl
	;; Negative means a run
	bit	7,e
	jp	Z,2$
	;; Code for expanding a run
	ld	a,(hl)
	inc	hl
3$:
	ld	(bc),a
	inc	bc
	inc	e
	jp	NZ,3$
	jp	1$
2$:
	;; Zero means end of a block
	xor	a
	or	e
	jp	Z,4$
	;; Code for expanding a block
5$:
	ld	a,(hl)
	inc	hl
	ld	(bc),a
	inc	bc
	dec	e
	jp	NZ,5$
	jp	1$
4$:
	;; Push the return address back onto the stack
	push	hl
	ret
