; =========================================================================
;  lib_startup.asm -- Sprinter EvoSDK runtime core (EvoSDK responsibility zone)
; =========================================================================
;  Mirrors evosdk/lib_startup.asm: DSS bootstrap + video mode, palette,
;  swap_screen/clear_screen, vsync/time/delay, misc runtime (memset/memcpy/
;  rand16/border), and the shared VRAM/asset helpers used by lib_tiles.
;  Graphics/sprites/sound/input live in lib_tiles/lib_sprites/lib_sound/
;  lib_input (separate .rel, linked together).
; =========================================================================

        .module lib_startup

        .globl  _evo_runtime_init
        .globl  _evo_runtime_shutdown
        .globl  _time_counter           ; frame counter low byte (lib_input mouse poll gate)

        .globl  _memset
        .globl  _memcpy
        .globl  _rand16
        .globl  _border
        .globl  _vsync
        .globl  _swap_screen
        .globl  _time
        .globl  _delay
        .globl  _pal_clear
        .globl  _pal_bright
        .globl  _pal_bright_fine
        .globl  _pal_select
        .globl  _pal_copy
        .globl  _pal_col
        .globl  _pal_custom
        .globl  _pal_load256
        .globl  _pal_set256
        .globl  _clear_screen

        ; --- shared helpers exported to lib_tiles.asm ---
        .globl  begin_vram_write
        .globl  end_vram_write
        .globl  _vram_base              ; back buffer base (#C000/#C140), set by begin_vram_write
        .globl  _sprites_render_before_swap
        .globl  _sprites_restore_after_swap
        .globl  _sound_tick
        .globl  _sync_tiles_to_shadow   ; from lib_tiles (dual-buffer tile sync)
        .globl  _evo_cbl_irq            ; from lib_sound (CBL refill on IM2 #FF)

        .area   _SDK

; ---- SDK runtime region in SRAM (#0000-#1FFF, mirror of EvoSDK #E000-#FFFF).
;      Loader fills the tables into chunk0 before LDIR'ing it into SRAM. These
;      EQUs MUST match loader.asm and lib_tiles.asm. ----
EVO_PAGE_TABLE  = 0x1A00         ; asset phys page table (200 B, #1A00-#1AC7), loader-filled
EVO_SAVED_VMODE = 0x1AC8         ; original DSS video mode (for exit), loader-filled
EVO_SAVED_W0    = 0x1AC9         ; original DSS WIN0 phys page (for exit), loader-filled
EVO_SAVED_W1    = 0x1ACA         ; original DSS WIN1 phys page (for exit), loader-filled
EVO_SAVED_W3    = 0x1ACB         ; original DSS WIN3 phys page (for exit), loader-filled
EVO_SAVED_MEM_CODE   = 0x1ACC    ; DSS code-block handle (we FreeMem it on exit), loader-filled
EVO_SAVED_MEM_ASSETS = 0x1ACD    ; DSS asset-block handle (0 = none), loader-filled
DSS_FREEMEM     = 0x3E           ; DSS.FreeMem: release a GetMem block (handle in A)
EVO_META        = 0x1B00         ; EVP1 header+metadata copy, loader-filled

; Sprinter page-register ports (WIN0..WIN3). WIN2 is the program's own window
; (loader/exit trampoline run there) and must NOT be restored on exit.
SLOT0_PORT      = 0x82
SLOT1_PORT      = 0xA2
SLOT3_PORT      = 0xE2
CBL_CTRL_PORT   = 0x89           ; CBL DAC / PORT_Y register

; The exit trampoline must execute with CACHE off (WIN0 = DSS BIOS, so SRAM is
; gone). We copy it -- and the values it needs -- transiently into WIN2 DRAM
; (the program is exiting, so clobbering C data there is harmless). No DRAM is
; reserved permanently.
EXIT_VMODE_DRAM = 0x8000
EXIT_CODE_DRAM  = 0x8001
EXIT_W0_DRAM    = 0x8002
EXIT_W1_DRAM    = 0x8003
EXIT_W3_DRAM    = 0x8004
EXIT_MEM_CODE_DRAM   = 0x8005    ; code-block handle, stashed to DRAM for the trampoline
EXIT_MEM_ASSETS_DRAM = 0x8006    ; asset-block handle (0 = none)
EXIT_TRAMP_DRAM = 0x8010
EXIT_TRAMP_SP   = 0xBF00

_evo_runtime_init::
        ; Runs in SRAM (CACHE on). Video mode (#81 on both pages) was set by the
        ; PRELOAD loader before cache-on -- the SRAM runtime makes NO DSS calls.
        di
        ld      hl, #1
        ld      (_rand_seed1), hl
        ld      hl, #5
        ld      (_rand_seed2), hl
        ld      a, #3
        ld      (_pal_bright_level), a

        call    evo_meta_init          ; cache EVP1 table bases (loader filled #1A00+)

        xor     a
        out     (#0xC9), a             ; visible screen A, blank bit clear
        ld      (_screen_active), a
        call    clear_both_buffers_black   ; runs DI (IM2 not yet enabled)
        call    _pal_clear
        ; CBL: the 256-byte FIFO can hold power-on garbage that plays as noise.
        ; Flush it with silence BEFORE arming, exactly like modplay
        ; InitCBL_PathA (cbl.asm): off -> flush 256 x 0x80 -> on. Then the idle
        ; arm keeps #FE.5 (frame source) toggling so _vsync polls it for the
        ; FRAME (tear-free, no IM2 dependence). Whole block is DI (we are pre-EI).
        ld      bc, #0x004E             ; CBL off
        xor     a
        out     (c), a
        ld      bc, #0x004F             ; flush FIFO: 256 x 0x80 (DAC centre)
        ld      a, #0x80
        ld      b, #0                   ; djnz from 0 = 256 (FIFO decodes C=#4F)
1$:
        out     (c), a
        djnz    1$
        ld      bc, #0x004E             ; CBL on (idle arm)
        ld      a, #0x80
        out     (c), a
        ; Joystick/Sega select: SIO chB /DTRB (WR5 bit7) drives J_SEL, which the
        ; 74HC257 mux uses to pick the gamepad's button set (sp-dx-sch sheet 7:
        ; /DTRB -> J_SEL -> mux -> X30 DB-9). Set it once to the "normal" set
        ; (dirs + FIRE1); the SDK only exposes the standard 2-button Kempston/Sega,
        ; so joystick() stays a plain IN A,(#1F) with no per-frame re-select.
        ; WR5 bit7=DTR per Z84C15 datasheet; #E0 also sets Tx 8bit/char (D6,D5).
        call    im2_sound_setup        ; CTC 50Hz IM2 -> _sound_tick + _time; EI
        .if FILEIO
        call    _dss_install_tramp     ; copy the DSS trampoline into its DRAM page
        .endif
        ret

; -------------------------------------------------------------------------
; im2_sound_setup: CTC channel 3 generates a 50 Hz IM2 interrupt that ticks
; sound (PT3 PLAY + AYFX FRAME) and the frame counter. The FRAME flip stays on
; the #FE.5 poll (_vsync) -- IM2 is only for stable music/time timing, exactly
; like evosdk_libs (crt0_game.s) + zx-sprinter-sdk. Vector table at #1F00 (SRAM,
; I=#1F) in the free reserve gap; whole table -> im2_empty so any non-CTC vector
; is a safe ei/reti. CTC CH3 vector #06 -> im2_sound_handler.
; CAUTION: with IM2 live, every accelerator block (sprites/sync/clear) must run
; DI so an IRQ can't fire mid-accel; those ops bracket themselves with di..ei.
; -------------------------------------------------------------------------
IM2_TABLE   = 0x1F00
CTC_CH0     = 0x10
CTC_CH2     = 0x12
CTC_CH3     = 0x13

im2_sound_setup:
        di
        ld      hl, #IM2_TABLE          ; fill table with im2_empty (safe default)
        ld      de, #im2_empty
        ld      b, #128
1$:
        ld      (hl), e
        inc     hl
        ld      (hl), d
        inc     hl
        djnz    1$
        ld      hl, #im2_sound_handler  ; CTC CH3 vector (base0 -> +6) -> handler
        ld      (IM2_TABLE + 6), hl
        ; Vector #FF: the Sprinter video/keyboard IRQ fires ~50 Hz with vector
        ; #FF (cf. evosdk_libs crt0_game.s setting 0xBEFF). With I=#1F it reads
        ; the pointer from #1FFF/#2000 -- straddling the table end into the stack
        ; bottom -- so it MUST be set to im2_empty or the CPU jumps to garbage
        ; (symptom: sound ticks from CTC #06 but the main code is derailed = no
        ; image). ld (#1FFF),hl writes L->#1FFF, H->#2000. #2000 is the lowest
        ; stack byte (only touched on a >1023 B overflow, already fatal).
        ld      hl, #_evo_cbl_irq       ; #FF: CBL half-empty refill OR plain video IRQ
        ld      (IM2_TABLE + 0xFF), hl
        ld      a, #0x1F
        ld      i, a
        im      2
        ld      a, #0x57                ; CTC CH2/CH3 chain -> ~50 Hz (evosdk_libs)
        out     (#CTC_CH2), a
        ld      a, #112
        out     (#CTC_CH2), a
        ld      a, #0xD7                ; CH3: bit7 = interrupt enable
        out     (#CTC_CH3), a
        ld      a, #160
        out     (#CTC_CH3), a
        xor     a
        out     (#CTC_CH0), a           ; CTC interrupt vector base = 0
        .if SAMPLE_ASYNC
        inc     a
        ld      (_snd_irq_ready), a     ; IM2 vectors live -> fill loops may now EI
        .endif
        ei
        ret

; IM2 handler (CTC, 50 Hz): bump 32-bit _time, then PT3/AFX frame. Full register
; save (sound tick pages memory + uses the alternate set). Mirrors evosdk_libs
; _evo_im2_handler. _sound_tick is only safe here because all accel ops run DI.
im2_sound_handler:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        .db     0x08                    ; ex af, af'
        exx
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, #_time_counter
        inc     (hl)
        jr      nz, 2$
        inc     hl
        inc     (hl)
        jr      nz, 2$
        inc     hl
        inc     (hl)
        jr      nz, 2$
        inc     hl
        inc     (hl)
2$:
        call    _sound_tick
        di                              ; _sound_tick's inner code may EI; re-DI
        pop     hl
        pop     de
        pop     bc
        pop     af
        exx
        .db     0x08                    ; ex af, af'
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ei
        reti

im2_empty:
        ei
        reti

; void quit_to_dss(void)
;   Sprinter-only public helper: return control to DSS with exit code 0. Thin
;   wrapper over evo_runtime_shutdown so games can quit from their own menu
;   (the normal exit path is crt0 falling off the end of main). Does not return.
_quit_to_dss::
        ld      l, #0
        ; fall through to _evo_runtime_shutdown

; void evo_runtime_shutdown(unsigned char exit_code)  [exit_code in L]
;   Copies a position-independent trampoline into a DRAM buffer (WIN2) and jumps
;   into it. The trampoline turns CACHE off (so RST #10 reaches the real DSS BIOS
;   at #0010), restores the DSS WIN0/WIN1/WIN3 pages + video mode saved by the
;   loader, silences the CBL DAC, restores IM1 + EI (DSS returns under IM1 and
;   HALT-waits for its timer IRQ -- staying in IM2 with IFF off hangs the BIOS),
;   then DSS.Exit. Does not return. (cf. evosdk_libs evo_exit.s, flappybird
;   set_im1/RestorePages, titd RESTORE_IM1_DSS. See HW_NOTES exit notes.)
_evo_runtime_shutdown::
        di
        ; Silence sound before returning to DSS, otherwise the last PT3 note keeps
        ; sounding on the AY and the CBL FIFO keeps draining. IM2 is off now (DI),
        ; so nothing rewrites these. Port I/O is paging-independent. L holds the
        ; exit code -- not touched here (only A/BC).
        ;   AY: select reg via #FFFD, write data via #BFFD. R7 mixer = all
        ;   tone/noise off; R8/R9/R10 volumes = 0 (silence each channel).
        ld      bc, #0xFFFD
        ld      a, #7
        out     (c), a
        ld      b, #0xBF
        ld      a, #0x3F
        out     (c), a                  ; mixer: tone+noise disabled
        ld      b, #0xFF
        ld      a, #8
        out     (c), a
        ld      b, #0xBF
        xor     a
        out     (c), a                  ; volume A = 0
        ld      b, #0xFF
        ld      a, #9
        out     (c), a
        ld      b, #0xBF
        xor     a
        out     (c), a                  ; volume B = 0
        ld      b, #0xFF
        ld      a, #10
        out     (c), a
        ld      b, #0xBF
        xor     a
        out     (c), a                  ; volume C = 0
        ; CBL: stop the FIFO controller (#004E) so a half-played sample halts.
        ld      bc, #0x004E
        xor     a
        out     (c), a
        ; CTC: we programmed CH2/CH3 for the 50 Hz IM2 sound tick (CH3 with its
        ; interrupt enabled). Left running, CH3 keeps raising interrupts after we
        ; hand back to DSS, which derails the next program's CTC/IM2 setup (e.g.
        ; TMNT fails to start). Reset both (control word #03 = sw reset + interrupt
        ; off) -> idle. (The CTC is write-only, so we can't restore DSS's exact
        ; config; but DSS times off the 50 Hz video IRQ, not the CTC, so idle is the
        ; pre-launch state for it and a clean slate for the next program.)
        ld      a, #0x03
        out     (#CTC_CH2), a
        out     (#CTC_CH3), a
        ; Launcher runs in SRAM (CACHE on): stash exit code + the saved video
        ; mode and DSS page numbers (read from SRAM) into WIN2 DRAM, copy the
        ; trampoline to WIN2, run. The trampoline can't read SRAM (cache off).
        ld      a, l
        ld      (EXIT_CODE_DRAM), a
        ld      a, (EVO_SAVED_VMODE)
        ld      (EXIT_VMODE_DRAM), a
        ld      a, (EVO_SAVED_W0)
        ld      (EXIT_W0_DRAM), a
        ld      a, (EVO_SAVED_W1)
        ld      (EXIT_W1_DRAM), a
        ld      a, (EVO_SAVED_W3)
        ld      (EXIT_W3_DRAM), a
        ld      a, (EVO_SAVED_MEM_CODE)
        ld      (EXIT_MEM_CODE_DRAM), a
        ld      a, (EVO_SAVED_MEM_ASSETS)
        ld      (EXIT_MEM_ASSETS_DRAM), a
        ld      hl, #tramp_src
        ld      de, #EXIT_TRAMP_DRAM
        ld      bc, #tramp_end - tramp_src
        ldir
        jp      EXIT_TRAMP_DRAM

; Position-independent, straight-line trampoline body. Copied into WIN2 DRAM and
; run there so it survives CACHE off (which turns WIN0/SRAM into DSS BIOS). Only
; absolute addresses (ports + the transient values in WIN2), no internal jumps.
; WIN2 itself is left mapped (this code runs there) -- only WIN0/WIN1/WIN3 are
; restored to their DSS pages.
tramp_src:
        ld      sp, #EXIT_TRAMP_SP      ; DRAM stack (WIN0/SRAM gone after cache off)
        in      a, (#0x7B)              ; CACHE off -> WIN0 = DSS BIOS

        ; Silence the CBL DAC (avoid a stuck level/click on return to DSS).
        xor     a
        out     (CBL_CTRL_PORT), a

        ; Restore the DSS page layout the loader/crt0 clobbered (WIN0/1/3).
        ld      a, (EXIT_W0_DRAM)
        out     (SLOT0_PORT), a
        ld      a, (EXIT_W1_DRAM)
        out     (SLOT1_PORT), a
        ld      a, (EXIT_W3_DRAM)
        out     (SLOT3_PORT), a

        ; Restore DSS video mode (RST #10 reaches real BIOS now that cache is off).
        push    ix                      ; SetVMod clobbers IX
        ld      a, (EXIT_VMODE_DRAM)
        ld      b, #0
        ld      c, #0x50                ; DSS SetVMod (restore video mode)
        rst     #0x10
        pop     ix

        ld      a, #0xC0
        out     (CBL_CTRL_PORT), a      ; park PORT_Y at DSS-safe value

        ; Flush the keyboard before DSS resumes: the game ran IM2 (DSS's key ISR was
        ; off), so the last in-game keys sit in the SIO chA Rx FIFO. Drain it here
        ; while still DI -- otherwise DSS's IM1 handler (re-armed below) would move
        ; that stale key into its buffer and the shell would receive it. Mirrors
        ; KEYINTER.RESCAN: read RR0 (#19) bit0 = Rx avail, read data (#18) to consume.
tramp_flush_kbd:
        in      a, (#0x19)              ; SIO chA status (RR0)
        and     #1                      ; bit0 = Rx character available
        jr      z, tramp_kbd_done
        in      a, (#0x18)              ; read & discard the scancode
        jr      tramp_flush_kbd
tramp_kbd_done:

        ; DSS runs under IM1 and HALT-waits for its timer IRQ on return; the game
        ; ran IM2 with IFF off here, so re-arm IM1 + EI before handing back.
        im      1
        ei

        ; Return our DSS memory blocks before leaving (good manners; DSS also frees
        ; them on Exit, but a program should release what it allocated). FreeMem
        ; clears the block's ownership, so the subsequent Exit does not double-free.
        ; Asset block first (we are NOT executing from it); the code block LAST --
        ; this trampoline runs in WIN2, part of the code block, so free it immediately
        ; before Exit: no allocation happens in between, so the just-freed page is not
        ; reused while we still run the final instructions from it. (jr is relative ->
        ; position-independent after the copy to WIN2 DRAM.)
        ld      a, (EXIT_MEM_ASSETS_DRAM)
        or      a
        jr      z, tramp_no_assets
        ld      c, #DSS_FREEMEM         ; release the asset block (handle in A)
        rst     #0x10
tramp_no_assets:
        ld      a, (EXIT_MEM_CODE_DRAM)
        ld      c, #DSS_FREEMEM         ; release the code block (handle in A)
        rst     #0x10

        ld      a, (EXIT_CODE_DRAM)
        ld      b, a
        ld      c, #0x41                ; DSS.Exit (does not return)
        rst     #0x10
tramp_end:

_memset::
        push    iy
        ld      iy, #4
        add     iy, sp
        ld      e, 0 (iy)               ; dst
        ld      d, 1 (iy)
        ld      c, 3 (iy)               ; len
        ld      b, 4 (iy)
        ld      a, b
        or      c
        jr      nz, 1$
        pop     iy
        ret
1$:
        ld      a, 2 (iy)               ; value
        pop     iy
        ld      l, e
        ld      h, d
        ld      (hl), a
        dec     bc
        ld      a, b
        or      c
        ret     z
        inc     de
        ldir
        ret

_memcpy::
        push    iy
        ld      iy, #4
        add     iy, sp
        ld      e, 0 (iy)               ; dst
        ld      d, 1 (iy)
        ld      l, 2 (iy)               ; src
        ld      h, 3 (iy)
        ld      c, 4 (iy)               ; len
        ld      b, 5 (iy)
        pop     iy
        ld      a, b
        or      c
        ret     z
        ldir
        ret

_rand16::
        ld      hl, (_rand_seed1)
        push    hl
        srl     h
        rr      l
        ex      de, hl
        ld      hl, (_rand_seed2)
        add     hl, de
        ld      (_rand_seed2), hl
        ld      a, l
        xor     #15
        ld      l, a
        ex      de, hl
        pop     hl
        sbc     hl, de
        ld      (_rand_seed1), hl
        ret

_border::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        and     #7
        out     (#0xFE), a              ; EvoSDK-compatible border port
        ret

_vsync::
        ; Tear-free frame sync by polling #FFFE bit5 (1 = bottom blank Y>256,
        ; 0 = active). Wait until ACTIVE (bit5=0), then until the blank STARTS
        ; (bit5 0->1) and return there so the caller flips in the blank. Catches
        ; the next blank in <=1 frame, no extra full cycle. CBL armed once in
        ; runtime_init. Pure polling (no interrupts needed). HW_NOTES §6.4.
        ; _time is advanced by the CTC IM2 handler, not here.
        ld      de, #0x8000             ; timeout guard so we never hang
1$:                                     ; wait until bit5 = 0 (active display)
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        jr      z, 2$
        dec     de
        ld      a, d
        or      e
        jr      nz, 1$
        ret                             ; timeout: do not hang
2$:                                     ; wait until bit5 = 1 (blank start = flip)
        ld      de, #0x8000
3$:
        ld      a, #0xFF
        in      a, (#0xFE)
        bit     5, a
        ret     nz
        dec     de
        ld      a, d
        or      e
        jr      nz, 3$
        ret

_swap_screen::
        call    _sprites_render_before_swap
        call    _vsync
        in      a, (#0xC9)              ; flappybird model: read current RGMOD.0
        xor     #0x01
        and     #0x01
        out     (#0xC9), a
        ld      (_screen_active), a
        call    _sprites_restore_after_swap
        call    _sync_tiles_to_shadow   ; propagate partial tile updates to the
        ret                             ; new hidden buffer (keeps buffers in sync)

_time::
        ld      hl, #_time_counter + 3
        ld      d, (hl)
        dec     hl
        ld      e, (hl)
        dec     hl
        ld      a, (hl)
        dec     hl
        ld      l, (hl)
        ld      h, a
        ret

_delay::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      a, d
        or      e
        ret     z
1$:
        push    de
        call    _vsync
        pop     de
        dec     de
        ld      a, d
        or      e
        jr      nz, 1$
        ret

inc_time_counter:
        call    _sound_tick
        ld      hl, #_time_counter
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret     nz
        inc     hl
        inc     (hl)
        ret

; Double buffer -- model used by flappybird grx_utils.asm and
; sdcc-sprinter-sdk/lib/gfx/gfx_lowlevel.s. DSS SetVMod #81 must be called
; for screen pages B=1 and B=0 by the loader. Runtime drawing maps a SINGLE
; VRAM page #50 into WIN3. For the selected PORT_Y(#89) scanline, CPU writes
; buffer 0 at #C000+x and buffer 1 at #C140+x (320 bytes apart). RGMOD(#C9).0
; selects the displayed buffer; back buffer = !visible.
VRAM_PAGE       = 0x50
VRAM_BUF0_BASE  = 0xC000
VRAM_BUF1_BASE  = 0xC140
        .if NATIVE
VRAM_Y_OFFSET   = 0                     ; native: full 320x256 surface (clear fills all 256)
        .else
VRAM_Y_OFFSET   = 28                    ; compat: centre 200-row Evo surface in 256 rows
        .endif

clear_both_buffers_black:
        in      a, (#0xE2)
        ld      (_vram_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        ld      c, #0                   ; black
        ld      hl, #VRAM_BUF0_BASE
        call    fill_buffer_320x256
        ld      hl, #VRAM_BUF1_BASE
        call    fill_buffer_320x256
        jp      end_vram_write

_clear_screen::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; C = color (preserved across fills)
        di                              ; block IM2 (sound) during accel fills
        call    begin_vram_write        ; WIN3 = #50
        ; EvoSDK clear_screen() clears the shadow/back screen only. Many games
        ; draw the same room twice around swap_screen() to seed both buffers;
        ; clearing the visible buffer here breaks overlay/dialog rendering.
        ld      hl, (_vram_base)
        call    fill_buffer_320x256
        call    end_vram_write
        ei
        ret

; begin_vram_write: WIN3 = page #50; select the HIDDEN (back) buffer base.
; Returns #C000 when visible is buffer 1, #C140 when visible is buffer 0.
begin_vram_write::
        in      a, (#0xE2)
        ld      (_vram_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        in      a, (#0xC9)
        and     #1                      ; visible buffer (0/1)
        ld      hl, #VRAM_BUF1_BASE     ; visible 0 -> draw hidden buffer 1
        jr      z, 1$
        ld      hl, #VRAM_BUF0_BASE     ; visible 1 -> draw hidden buffer 0
1$:
        ld      (_vram_base), hl
        ret

end_vram_write::
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_vram_saved_win3)
        out     (#0xE2), a
        ret

fill_buffer_320x256:
        ; In: HL = row base (#C000/#C140, page #50 in WIN3), C = color.
        ; Fills all 256 scanlines. Sprinter row window is selected by PORT_Y;
        ; 320 pixels are two 160-byte accel fills (block-size latch is 8-bit).
        xor     a
1$:
        out     (#0x89), a
        push    af
        push    hl
        call    fill_row_320
        pop     hl
        pop     af
        inc     a
        jr      nz, 1$
        ret

fill_row_320:
        push    hl

        di
        ld      d, d                    ; accel: size mode
        ld      a, #160
        ld      c, c                    ; accel: horizontal fill mode
        ld      a, c
        ld      (hl), a                 ; accel fire: first 160 bytes
        ld      b, b                    ; accel off
        .if SAMPLE_ASYNC
        ld      a, (_snd_irq_ready)     ; EI only once IM2 is live (NOT during init's
        or      a                       ; clear_both_buffers_black -- no vectors yet)
        jr      z, 2$
        ei                              ; IRQ window between accel fills (async refill)
2$:
        .endif

        ld      a, #160
        add     a, l
        ld      l, a
        jr      nc, 1$
        inc     h
1$:
        di
        ld      d, d
        ld      a, #160
        ld      c, c
        ld      a, c
        ld      (hl), a                 ; accel fire: second 160 bytes
        ld      b, b
        .if SAMPLE_ASYNC
        ld      a, (_snd_irq_ready)
        or      a
        jr      z, 3$
        ei                              ; IRQ window before the next row / caller
3$:
        .endif

        pop     hl
        ret

; -------------------------------------------------------------------------
;  Palette (EvoSDK lib_startup zone). Direct protocol from HW_NOTES.md §3:
;  WIN3=#50, PORT_Y=index. BIOS PIC_SET_PAL uses palette page A as an offset
;  inside the same VRAM page: page 0 at #C3E0..#C3E3, page 1 at #C3E4..#C3E7.
;  Direct writes therefore update both offsets, not VRAM page #55.
; -------------------------------------------------------------------------
_pal_clear::
        xor     a
        ld      (_active_pal_is256), a  ; cleared palette uses the 16-colour path
        ld      (_active_pal_is_cptr), a
        ld      hl, #_palette
        ld      b, #16
        xor     a
1$:
        ld      (hl), a
        inc     hl
        djnz    1$

        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    clear_pal_banks
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
        ret

clear_pal_banks:                        ; WIN3 = #50; zero both palette banks
        ld      b, #0
2$:
        ld      a, b
        out     (#0x89), a
        xor     a
        ld      (#0xC3E0), a
        ld      (#0xC3E1), a
        ld      (#0xC3E2), a
        ld      (#0xC3E3), a
        ld      (#0xC3E4), a
        ld      (#0xC3E5), a
        ld      (#0xC3E6), a
        ld      (#0xC3E7), a
        djnz    2$
        ret

_pal_bright::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        cp      #7
        jr      c, 1$
        ld      a, #6
1$:
        ld      (_pal_bright_level), a
        ld      a, (_active_pal_is256)
        or      a
        jr      nz, pal_bright_256
        jp      apply_palette_all
pal_bright_256:
        ; 256-colour fade: re-read the active palette and re-apply it scaled by the
        ; new brightness (no 256-entry SRAM buffer needed).
        ld      a, (_active_pal_is_cptr)
        or      a
        jr      nz, pal_bright_256_cptr
        ld      a, (_active_pal_id)
        call    map_palette_page        ; HL = payload, WIN1 saved
        call    apply_palette_256
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        ret
pal_bright_256_cptr:
        ; source is a flat C buffer (pal_load256): re-apply from the saved pointer.
        call    build_coarse_lut        ; pal_lut8 for the new _pal_bright_level
        ld      hl, (_active_pal_cptr)
        jp      apply_palette_256_run_flat

; pal_bright_fine(u8 level): fine-grained brightness, level = 0..32 (32 = normal,
; full colour; 0 = black). Sprinter-only extension for smooth fades -- the coarse
; pal_bright(0..6) gives only 4 steps in the fade range, which bands visibly on
; 256-colour photos. level gives 32 linear steps. For a 256-colour palette each
; 6-bit channel is scaled by level/32 (built into a 64-byte table, no per-entry
; multiply); for a 16-colour palette level maps to the nearest coarse level (flat
; art needs no finer fade). Public pal_bright / BRIGHT_* macros are unchanged.
_pal_bright_fine::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; level (0..32)
        cp      #33
        jr      c, 1$
        ld      a, #32
1$:
        ld      (_fine_bright_level), a
        ld      a, (_active_pal_is256)
        or      a
        jr      nz, pal_bright_fine_256
        ; 16-colour: coarse = round(level*3/32) = (level*3+16)>>5, then reuse path
        ld      a, (_fine_bright_level)
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a
        add     hl, hl
        add     hl, de                  ; level*3
        ld      de, #16
        add     hl, de                  ; level*3+16
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l                       ; >>5 -> L = 0..3
        ld      a, l
        ld      (_pal_bright_level), a
        jp      apply_palette_all
pal_bright_fine_256:
        ld      a, (_active_pal_is_cptr)
        or      a
        jr      nz, pal_bright_fine_256_cptr
        ld      a, (_active_pal_id)
        call    map_palette_page        ; HL = payload, WIN1 saved
        call    apply_palette_256_fine
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        ret
pal_bright_fine_256_cptr:
        ; flat C buffer (pal_load256): build the fine LUT and re-apply from pointer.
        ld      a, (_fine_bright_level)
        call    build_lut_fine          ; A = level -> pal_lut8
        ld      hl, (_active_pal_cptr)
        jp      apply_palette_256_run_flat

_pal_col::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; id
        and     #15
        ld      c, a
        inc     hl
        ld      a, (hl)                 ; RGB222 color
        ld      b, #0
        ld      hl, #_palette
        add     hl, bc
        ld      (hl), a                 ; store color into _palette[id]
        xor     a
        ld      (_active_pal_is256), a  ; back to the 16-entry RGB222 update path
        ld      (_active_pal_is_cptr), a
        jp      apply_palette_all       ; re-apply whole palette

_pal_custom::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ex      de, hl
        ld      de, #_palette
        ld      bc, #16
        ldir
        xor     a
        ld      (_active_pal_is256), a  ; back to the 16-entry RGB222 update path
        ld      (_active_pal_is_cptr), a
        jp      apply_palette_all

_pal_copy::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; palette id
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = user RGB222[16] dest
        push    de
        call    map_palette_page        ; HL = payload in WIN1, WIN1 saved
        pop     de
        call    copy_palette_payload
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        ret

_pal_select::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; palette id
        ld      (_active_pal_id), a     ; remember for pal_bright re-apply
        push    af
        xor     a
        ld      (_active_pal_is_cptr), a ; source is a paged asset, not a C buffer
        pop     af
        call    map_palette_page        ; HL = payload in WIN1, WIN1 saved
        ; payload = [u16 count][...]; count high byte != 0  =>  256-colour
        inc     hl
        ld      a, (hl)                 ; count high byte
        dec     hl                      ; HL back to payload[0]
        or      a
        jr      nz, pal_select_256
        ; --- 16-colour path (RGB222), unchanged ---
        xor     a
        ld      (_active_pal_is256), a
        ld      de, #_palette
        call    copy_palette_payload
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        jp      apply_palette_all
pal_select_256:
        ld      a, #1
        ld      (_active_pal_is256), a
        call    apply_palette_256       ; HL = payload; writes all 256 entries
        ld      a, (_pal_saved_win1)
        out     (#0xA2), a              ; restore WIN1
        ret

; void pal_load256(const void *pal): apply a full 256-colour palette from a flat C
; buffer (256 * (R8,G8,B8) = 768 bytes, no count prefix), at full 8-bit depth
; scaled by the current coarse brightness. Marks the 256-colour path active and is
; a C-buffer source, so pal_bright[_fine] re-apply from the saved pointer.
_pal_load256::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = pal pointer
        ld      (_active_pal_cptr), de
        ld      a, #1
        ld      (_active_pal_is256), a
        ld      (_active_pal_is_cptr), a
        call    build_coarse_lut        ; pal_lut8 for current _pal_bright_level
        ld      hl, (_active_pal_cptr)
        jp      apply_palette_256_run_flat   ; HL = first triple; writes 256, ret

; void pal_set256(u8 index, u8 r, u8 g, u8 b): set one 256-colour entry at full
; 8-bit depth. Channels pass through pal_lut8 (current brightness), so the entry
; matches any active fade. Leaves the 16/256 mode flags untouched. Precondition:
; a 256-colour palette is active (pal_lut8 built by the last pal_select/pal_load256/
; pal_bright). Overwritten on the next full palette apply.
_pal_set256::
        push    ix
        ld      ix, #4
        add     ix, sp                  ; IX -> args (index,r,g,b); +2 for pushed IX
        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a              ; WIN3 = #50 for #C3Ex
        ld      a, 0 (ix)               ; index
        out     (#0x89), a              ; PORT_Y = index
        ld      de, #pal_lut8
        ld      a, 1 (ix)               ; R8
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (hl)
        ld      (#0xC3E0), a
        ld      (#0xC3E4), a
        ld      a, 2 (ix)               ; G8
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (hl)
        ld      (#0xC3E1), a
        ld      (#0xC3E5), a
        ld      a, 3 (ix)               ; B8
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (hl)
        ld      (#0xC3E2), a
        ld      (#0xC3E6), a
        xor     a
        ld      (#0xC3E3), a
        ld      (#0xC3E7), a
        ld      a, #0xC0
        out     (#0x89), a              ; PORT_Y back to default
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a              ; restore WIN3
        pop     ix
        ret

copy_palette_payload:
        ; In: HL = EVOS PAL payload ([u16 count][count*(R,G,B)]),
        ;     DE = destination RGB222[16].
        inc     hl
        inc     hl
        ld      b, #16
1$:
        ld      a, (hl)                 ; R8
        inc     hl
        rlca
        rlca
        and     #3
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        ld      c, a

        ld      a, (hl)                 ; G8
        inc     hl
        rlca
        rlca
        and     #3
        add     a, a
        add     a, a
        or      c
        ld      c, a

        ld      a, (hl)                 ; B8
        inc     hl
        rlca
        rlca
        and     #3
        or      c
        ld      (de), a
        inc     de
        djnz    1$
        ret

; apply_palette_all: write _palette[16] to both screen palette banks.
apply_palette_all:
        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a
        call    apply_pal_banks
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
        ret

apply_pal_banks:                        ; WIN3 = #50
        ld      hl, #_palette
        ld      c, #0
3$:
        ld      a, (hl)
        push    hl
        call    write_palette_entry
        pop     hl
        inc     hl
        inc     c
        ld      a, c
        cp      #16
        jr      nz, 3$
        ret

write_palette_entry:
        ; C = palette index, A = RGB222. Hardware wants 6-bit channel values
        ; in bits 7..2, so pal_bright_table stores pre-shifted values.
        push    bc
        ld      e, a
        ld      a, c
        out     (#0x89), a

        ld      a, (_pal_bright_level)
        add     a, a
        add     a, a
        ld      l, a
        ld      h, #0
        ld      bc, #pal_bright_table
        add     hl, bc

        ld      a, e                    ; red = bits 4..5
        rrca
        rrca
        rrca
        rrca
        and     #3
        push    hl
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E0), a
        ld      (#0xC3E4), a
        pop     hl

        ld      a, e                    ; green = bits 2..3
        rrca
        rrca
        and     #3
        push    hl
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E1), a
        ld      (#0xC3E5), a
        pop     hl

        ld      a, e                    ; blue = bits 0..1
        and     #3
        ld      c, a
        ld      b, #0
        add     hl, bc
        ld      a, (hl)
        ld      (#0xC3E2), a
        ld      (#0xC3E6), a
        xor     a
        ld      (#0xC3E3), a
        ld      (#0xC3E7), a
        pop     bc
        ret

; apply_palette_256: write all 256 palette entries (§9.1, 256-colour path) at
;   FULL 8-bit depth. In: HL = EVOS PAL payload ([u16 count][256*(R8,G8,B8)])
;   mapped in WIN1. The Sprinter palette register is 8 bits/channel (0..255 --
;   manual 05_graphics/05_palette "4 байта на цвет: R,G,B 0..255"); the old
;   RGB6<<2 path silently dropped the low 2 bits of every channel. Each 8-bit
;   channel is now mapped through pal_lut8[256] (the current-brightness curve)
;   and written verbatim. Writes both palette banks at PORT_Y=index, WIN3=#50.
;   Caller restores WIN1. Coarse-brightness entry: builds pal_lut8 from
;   _pal_bright_level (curve identical to the old bright6_table at MID/anchors).
apply_palette_256:
        push    hl                      ; save payload pointer
        call    build_coarse_lut        ; pal_lut8 for current _pal_bright_level
        pop     hl                      ; HL = payload again
        jr      apply_palette_256_run

; build_coarse_lut: build pal_lut8 from _pal_bright_level (coarse 0..6).
;   level<=3 darken: lut[i]=round(i*level/3). level>3 brighten:
;   lut[i]=round(i+(255-i)*(level-3)/3) = round((i*(6-level)+255*(level-3))/3)
;   -> step=6-level, q0=85*(level-3). MID(3) -> identity (full 8-bit precision).
;   Clobbers A, B, C, D, E, HL.
build_coarse_lut:
        ld      a, (_pal_bright_level)
        cp      #4
        jr      nc, bcl_bright
        ld      c, a                    ; step = level
        ld      d, #0                   ; q0 = 0
        jr      bcl_build
bcl_bright:
        ld      b, a                    ; save level
        ld      a, #6
        sub     b
        ld      c, a                    ; step = 6 - level
        ld      a, b
        sub     #3                      ; k = level - 3 (1..3)
        ld      e, a
        ld      d, #0
        ld      hl, #q0_85k
        add     hl, de
        ld      d, (hl)                 ; q0 = 85*k
bcl_build:
        jp      build_lut_div3          ; C=step, D=q0 -> pal_lut8 (tail call)

q0_85k:
        .db     0, 85, 170, 255         ; 85*k for k = 0..3

apply_palette_256_fine:
        ; fine brightness 0..32 (32 = normal): build pal_lut8[i] = round(i*level/32).
        push    hl                      ; save payload pointer
        ld      a, (_fine_bright_level)
        call    build_lut_fine          ; A = level -> pal_lut8
        pop     hl                      ; HL = payload again
        ; fall through to the shared writer

apply_palette_256_run:
        ; HL = EVOS PAL payload ([u16 count][triples]); skip the count prefix.
        inc     hl
        inc     hl
apply_palette_256_run_flat:
        ; HL = first RGB triple (flat 256*(R8,G8,B8), no count prefix).
        push    ix
        push    hl
        pop     ix                      ; IX = first RGB triple
        in      a, (#0xE2)
        ld      (_pal_saved_win3), a
        ld      a, #VRAM_PAGE
        out     (#0xE2), a              ; WIN3 = #50 for #C3Ex
        ld      de, #pal_lut8           ; DE = brightness LUT base (kept across loop)
        ld      c, #0                   ; palette index 0..255
pal256_loop:
        ld      a, c
        out     (#0x89), a              ; PORT_Y = index
        ld      a, 0 (ix)               ; R8
        ld      l, a
        ld      h, #0
        add     hl, de                  ; pal_lut8 + R8
        ld      a, (hl)                 ; full 8-bit channel value
        ld      (#0xC3E0), a
        ld      (#0xC3E4), a
        ld      a, 1 (ix)               ; G8
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (hl)
        ld      (#0xC3E1), a
        ld      (#0xC3E5), a
        ld      a, 2 (ix)               ; B8
        ld      l, a
        ld      h, #0
        add     hl, de
        ld      a, (hl)
        ld      (#0xC3E2), a
        ld      (#0xC3E6), a
        xor     a
        ld      (#0xC3E3), a
        ld      (#0xC3E7), a
        inc     ix
        inc     ix
        inc     ix                      ; next RGB triple
        inc     c
        ld      a, c
        or      a
        jr      nz, pal256_loop         ; 256 entries (C wraps 255 -> 0)
        ld      a, #0xC0
        out     (#0x89), a
        ld      a, (_pal_saved_win3)
        out     (#0xE2), a
        pop     ix
        ret

; build_lut_fine: pal_lut8[i] = (i*level + 16) >> 5, i = 0..255 (= round(i*level/32)).
;   In: A = fine level 0..32 (32 = identity). Division-free accumulator; built
;   once per fade step, then the writer does 256*3 plain table lookups.
;   Clobbers A, BC, DE, HL.
build_lut_fine:
        ld      c, a                    ; C = level (per-step increment)
        ld      hl, #pal_lut8
        ld      de, #16                 ; num = i*level + 16 (rounding bias)
        ld      b, #0                   ; 256 iterations (djnz wraps 0 -> 256)
blf_loop:
        push    de
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e                       ; de = num >> 5  (E = 0..255, D = 0)
        ld      a, e
        ld      (hl), a
        inc     hl
        pop     de
        ld      a, c
        add     a, e
        ld      e, a
        jr      nc, blf_next
        inc     d                       ; carry into high byte
blf_next:
        djnz    blf_loop
        ret

; build_lut_div3: pal_lut8[i] = q, where q = q0 and advances by step/3 with
;   rounding (rem seeded to 1 ~ +0.5). In: C = step (0..3), D = q0 (0..255).
;   Division-free (rem < 3, <=2 subtractions/step). Clobbers A, B, DE, HL.
build_lut_div3:
        ld      hl, #pal_lut8
        ld      e, #1                   ; rem = rounding bias
        ld      b, #0                   ; 256 iterations
bd3_loop:
        ld      a, d
        ld      (hl), a                 ; lut[i] = q
        inc     hl
        ld      a, e
        add     a, c                    ; rem += step
bd3_adj:
        cp      #3
        jr      c, bd3_done
        sub     #3
        inc     d                       ; q++
        jr      bd3_adj
bd3_done:
        ld      e, a                    ; rem
        djnz    bd3_loop
        ret

; -------------------------------------------------------------------------
;  EVP1 paged asset access (HW_NOTES §9.2, §15). The loader copied the EVP1
;  header+metadata to EVO_META (#1B00, SRAM). Tables are ID-indexed; access is
;  O(1): table_base + id*stride, then map one page into WIN1.
;
;  EVO_META layout: [16B EVP2 header][u8 img_count][img*5]
;                   [u8 pal_count][pal*3:{u8 page,u16 off}][...]
;  Fixed: img_count @ EVO_META+16, img table @ +17. pal table base depends on
;  img_count -> computed once by evo_meta_init.
; -------------------------------------------------------------------------
EVO_PAGE_TABLE  = 0x1A00                ; asset phys page table (loader-filled)
EVO_META_IMGCNT = 0x1B10                ; EVO_META + 16
EVO_IMG_TABLE   = 0x1B11                ; EVO_META + 17

evo_meta_init:
        ; _pal_base = EVO_IMG_TABLE + img_count*5 + 1 (skip pal_count byte)
        ld      a, (EVO_META_IMGCNT)
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = img_count
        add     hl, hl
        add     hl, hl                  ; img_count*4
        add     hl, de                  ; img_count*5
        ld      de, #EVO_IMG_TABLE
        add     hl, de                  ; -> pal_count byte
        inc     hl                      ; -> pal table
        ld      (_pal_base), hl
        ret

map_palette_page:
        ; In: A = palette id. Out: HL = payload in WIN1 (#4000+off); WIN1
        ; saved in _pal_saved_win1 (caller restores). record = _pal_base+id*3,
        ; record = { u8 logical_page, u16 offset }. The logical page must be
        ; resolved through page_table to a physical page (same as draw_tile).
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, l
        add     hl, hl                  ; id*2
        add     hl, de                  ; id*3
        ld      de, (_pal_base)
        add     hl, de                  ; -> record {u8 page, u16 off}
        ld      a, (hl)                 ; logical page
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = offset
        ; phys = page_table[logical]
        push    de                      ; save offset
        ld      e, a
        ld      d, #0
        ld      hl, #EVO_PAGE_TABLE
        add     hl, de
        ld      a, (hl)                 ; physical page
        pop     de                      ; restore offset
        ld      c, a
        in      a, (#0xA2)
        ld      (_pal_saved_win1), a    ; save WIN1
        ld      a, c
        out     (#0xA2), a              ; map physical palette page into WIN1
        ld      hl, #0x4000
        add     hl, de                  ; HL = payload
        ret

pal_bright_table:
        ; brightness 0..6, channel 0..3, values pre-shifted for RGB6<<2.
        .db     0,   0,   0,   0
        .db     0,   28,  56,  84
        .db     0,   56,  112, 168
        .db     0,   84,  168, 252
        .db     84,  140, 196, 252
        .db     168, 196, 224, 252
        .db     252, 252, 252, 252

        .area   _SDKDATA
        ; SDK mutable data, in the SRAM region (#1600). Saved video mode for the
        ; exit trampoline lives in SRAM #1AC8 (loader-filled), read by the
        ; shutdown launcher before CACHE off.
_screen_active:
        .db     0
        .if SAMPLE_ASYNC
_snd_irq_ready:                         ; 0 until im2_sound_setup installs IM2 vectors;
        .db     0                       ; gates the narrowed-DI EI in the fill loop
        .endif
_time_counter:
        .db     0, 0, 0, 0
_rand_seed1:
        .dw     0
_rand_seed2:
        .dw     0
_palette:
        .db     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
_pal_bright_level:
        .db     0
_fine_bright_level:                             ; fine brightness 0..32 (32 = normal)
        .db     32
pal_lut8:                                  ; 256-byte 8-bit brightness LUT for the
        .ds     256                        ; 256-colour path, rebuilt per palette apply
; Active display palette tracking for the 256-colour path (§9.1). pal_select
; records which predefined palette is shown and whether it is 256-colour, so
; pal_bright can re-apply it (256-colour fade re-reads the asset, not a buffer).
_active_pal_id:
        .db     0
_active_pal_is256:
        .db     0
; pal_load256 source: when set, the active 256-colour palette lives in a flat C
; buffer (pointer below), not a paged asset. pal_bright[_fine] re-applies from it.
_active_pal_is_cptr:
        .db     0
_active_pal_cptr:
        .dw     0
_pal_saved_win3:
        .db     0
_vram_saved_win3:
        .db     0
_pal_saved_win1:
        .db     0
_pal_base:
        .dw     0
_vram_base:
        .dw     0
