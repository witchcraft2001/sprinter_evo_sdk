; Compatibility shims for helper symbols emitted by SDCC 2.9.0.
; Modern z80 runtime keeps compatible helper entry points under
; shorter names, so a tail-jump is sufficient.

	.module sdcc290_compat

	.globl __divulong_rrx_s
	.globl __modulong_rrx_s
	.globl __divulong
	.globl __modulong

	.area _CODE

__divulong_rrx_s::
	jp __divulong

__modulong_rrx_s::
	jp __modulong
