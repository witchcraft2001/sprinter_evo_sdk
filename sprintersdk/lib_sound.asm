; =========================================================================
;  lib_sound.asm -- music / sfx / sample playback (EvoSDK responsibility zone)
; =========================================================================
;  Public API: music_play/stop, sfx_play/stop, sample_play.
;  Этап 5 status:
;    - sample_play: EvoSDK-compatible blocking PCM playback through Sprinter CBL.
;    - music_play/stop: PT3 player page image is called from the polled frame tick.
;    - sfx_play/stop: AFX player page image is called from the polled frame tick.
;    - final IM2/CTC timing is still pending.
;
;  CBL facts: HW_NOTES.md §6.1 / modplay cbl.asm.
;    CBL_CTRL = #004E, CBL_DATA = #004F, use OUT (C),A with B=0.
;    #FE.bit7 is the half-FIFO indicator when the CBL control byte has bit4=1.
;    sample_play is blocking and DI, matching original EvoSDK semantics.
; =========================================================================

        .module lib_sound

        .globl  _sfx_play
        .globl  _sfx_stop
        .globl  _music_play
        .globl  _music_stop
        .globl  _sample_play
        .globl  _sound_tick
        .globl  _evo_cbl_irq            ; IM2 #FF vector hook (CBL refill / video IRQ)

        .area   _SDK

EVO_PAGE_TABLE  = 0x1A00                ; loader-filled phys page table
EVO_META_IMGCNT = 0x1B10                ; EVO_META + 16
EVO_IMG_TABLE   = 0x1B11                ; img records: u16 base, u8 wt, u8 ht, u8 flags

SLOT3       = 0xE2
CBL_CTRL    = 0x004E
CBL_DATA    = 0x004F
CBL_IDLE    = 0x80                      ; keeps #FE.5 vsync source active

_sfx_play::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; sfx id
        ld      (_sfx_id), a
        inc     hl
        ld      a, (hl)                 ; relative volume (-15..15)
        ld      (_sfx_vol), a

        call    sfx_record              ; HL -> sfx record, carry if absent
        ret     c

        ld      a, (hl)                 ; logical page with #C000 AFX image
        call    logical_to_phys_a
        ld      (_sfx_phys_page), a

        ld      a, (_sfx_initialized)
        or      a
        jr      nz, 1$
        call    sfx_call_init
        ld      a, #1
        ld      (_sfx_initialized), a
1$:
        ld      a, #1
        ld      (_sfx_active), a
        call    sfx_call_play
        ei                              ; restore IM2 (call paths run DI)
        ret

_sfx_stop::
        ld      a, (_sfx_initialized)
        or      a
        jr      z, 1$
        call    sfx_call_init           ; AFX INIT marks all channels empty
1$:
        xor     a
        ld      (_sfx_active), a
        ei
        ret

_music_play::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; music id
        call    music_record_a          ; HL -> music record, carry if missing
        ret     c

        ld      a, (hl)                 ; logical page with #C000 PT3 image
        call    logical_to_phys_a
        ld      (_music_phys_page), a
        call    music_call_init
        ld      a, #1
        ld      (_music_active), a
        ei                              ; restore IM2 (music_call_* run DI)
        ret

_music_stop::
        ld      a, (_music_active)
        or      a
        ret     z
        call    music_call_mute
        xor     a
        ld      (_music_active), a
        ei
        ret

; -------------------------------------------------------------------------
; sample_play(u8 sample)
; EVP2 sample table layout:
;   [img_count][img*5][pal_count][pal*3][mus_count][mus*5]
;   [smp_count][smp*6:{u8 logical_page,u16 off,u16 len,u8 cbl}]
; Streams len bytes, then enough #80 silence to align to 128 plus one full
; FIFO (256 bytes). Samples may cross 16K logical pages.
; -------------------------------------------------------------------------
_sample_play::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; sample id
        call    sample_record_a         ; HL -> sample record, carry if missing
        ret     c

        ld      a, (hl)                 ; logical page
        ld      (_cbl_logical_page), a
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = offset inside logical page
        inc     hl
        ld      c, (hl)
        inc     hl
        ld      b, (hl)                 ; BC = sample length
        inc     hl
        ld      a, (hl)                 ; CBL mode byte (#D9/#DA/#DB)
        or      a
        jr      nz, 1$
        ld      a, #0x99                ; defensive default: mono 8-bit, INT, 11 kHz
1$:
        ld      (_cbl_ctrl), a

        ld      a, b
        or      c
        ret     z                       ; empty sample

        ld      (_cbl_sample_remaining), bc
        call    compute_silence_tail_bc ; BC=len -> HL=tail bytes
        ld      (_cbl_tail_remaining), hl

        ; Initial sample pointer = #C000 + offset.
        ld      hl, #0xC000
        add     hl, de
        ld      (_cbl_sample_ptr), hl

        di
        in      a, (#SLOT3)
        ld      (_cbl_saved_win3), a

        ; CBL off, then flush 256 center samples. B must stay zero: the high
        ; byte of BC is on the Z80 I/O address bus, so no OTIR/DJNZ on B.
        ld      bc, #CBL_CTRL
        xor     a
        out     (c), a
        call    cbl_flush_256

        ld      a, (_cbl_logical_page)
        call    map_logical_page_win3

        ; CBL on at the sample's recorded rate. Bit4 is already set by
        ; assetpack.cbl_ctrl_for_rate(), enabling #FE.bit7.
        ld      bc, #CBL_CTRL
        ld      a, (_cbl_ctrl)
        out     (c), a

        ; Arm IRQ-driven streaming: the #FF IM2 vector (_evo_cbl_irq) refills the
        ; FIFO on each CBL half-empty event (proven HW path, cf. MK_OUTI). The
        ; blocking foreground HALT-waits until the handler has fed the whole sample
        ; plus the silence tail, matching EvoSDK's blocking sample_play semantics.
        ld      a, #1
        ld      (_cbl_active), a
        ld      de, #4000               ; anti-hang guard: bail if no IRQ clears it
        ei
sample_wait_active:
        halt
        ld      a, (_cbl_active)
        or      a
        jr      z, sample_wait_done
        dec     de
        ld      a, d
        or      e
        jr      nz, sample_wait_active
        xor     a                       ; timeout -> force-stop streaming
        ld      (_cbl_active), a
sample_wait_done:

        ; Drain: let the last FIFO contents (silence tail) play out, then leave CBL
        ; in idle mode so video vsync polling (#FE.5) keeps working.
        ld      b, #4
sample_drain_halt:
        halt
        djnz    sample_drain_halt

        ld      bc, #CBL_CTRL
        ld      a, #CBL_IDLE
        out     (c), a
        ld      a, (_cbl_saved_win3)
        out     (#SLOT3), a
        ret

; _evo_cbl_irq: IM2 vector #FF (shared by the video/keyboard IRQ and CBL). If a
; sample is streaming and #FE.bit7 (CBL_IND = CNT7^WA7, half-FIFO) is set, this is
; a CBL half-empty event -> refill 128 bytes; otherwise it is a plain video IRQ ->
; just ei/reti. WIN3 is saved and remapped to the current sample page around the
; refill so it is robust against whatever the foreground / other IRQs left there.
_evo_cbl_irq::
        push    af
        ld      a, (_cbl_active)
        or      a
        jr      z, cbl_irq_ret          ; no active sample -> plain video IRQ
        in      a, (#0xFE)
        and     #0x80
        jr      z, cbl_irq_ret          ; bit7=0 -> not a CBL half-empty event
        push    bc
        push    de
        push    hl
        .db     0x08                    ; ex af,af' (cbl_stream_128 uses A')
        push    af
        in      a, (#SLOT3)
        ld      (_cbl_irq_saved_win3), a
        ld      a, (_cbl_logical_page)
        call    map_logical_page_win3
        call    cbl_stream_128
        ld      a, (_cbl_irq_saved_win3)
        out     (#SLOT3), a
        ; sample + tail both drained -> signal the foreground to stop
        ld      hl, (_cbl_sample_remaining)
        ld      a, h
        or      l
        jr      nz, cbl_irq_busy
        ld      hl, (_cbl_tail_remaining)
        ld      a, h
        or      l
        jr      nz, cbl_irq_busy
        xor     a
        ld      (_cbl_active), a
cbl_irq_busy:
        pop     af
        .db     0x08                    ; ex af,af'
        pop     hl
        pop     de
        pop     bc
cbl_irq_ret:
        pop     af
        ei
        reti

; sample_record_a: A = sample id. Out HL = record, carry on missing/out of range.
sample_record_a:
        ld      b, a                    ; keep sample id in B (skips preserve B)

        ld      a, (EVO_META_IMGCNT)
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = img_count
        add     hl, hl
        add     hl, hl                  ; img_count*4
        add     hl, de                  ; img_count*5
        ld      de, #EVO_IMG_TABLE
        add     hl, de                  ; -> pal_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_3          ; -> mus_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_5          ; -> smp_count

        ld      a, b                    ; sample id
        cp      (hl)
        jr      nc, sample_record_missing
        inc     hl                      ; -> smp table
        ld      e, a
        ld      d, #0
        add     hl, de                  ; id*1
        add     hl, de                  ; id*2
        add     hl, de                  ; id*3
        add     hl, de                  ; id*4
        add     hl, de                  ; id*5
        add     hl, de                  ; id*6
        or      a                       ; clear carry
        ret
sample_record_missing:
        scf
        ret

; music_record_a: A = music id. Out HL = record {page,off,len}, carry if missing.
music_record_a:
        ld      b, a                    ; keep music id in B (skips preserve B)

        ld      a, (EVO_META_IMGCNT)
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = img_count
        add     hl, hl
        add     hl, hl                  ; img_count*4
        add     hl, de                  ; img_count*5
        ld      de, #EVO_IMG_TABLE
        add     hl, de                  ; -> pal_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_3          ; -> mus_count

        ld      a, b                    ; music id
        cp      (hl)
        jr      nc, music_record_missing
        inc     hl                      ; -> mus table
        ld      e, a
        ld      d, #0
        add     hl, de                  ; id*1
        add     hl, de                  ; id*2
        add     hl, de                  ; id*3
        add     hl, de                  ; id*4
        add     hl, de                  ; id*5
        or      a
        ret
music_record_missing:
        scf
        ret

sfx_record:
        ld      a, (EVO_META_IMGCNT)
        ld      l, a
        ld      h, #0
        ld      d, h
        ld      e, a                    ; de = img_count
        add     hl, hl
        add     hl, hl                  ; img_count*4
        add     hl, de                  ; img_count*5
        ld      de, #EVO_IMG_TABLE
        add     hl, de                  ; -> pal_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_3          ; -> mus_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_5          ; -> smp_count

        ld      a, (hl)
        inc     hl
        call    skip_a_times_6          ; -> sfx_present

        ld      a, (hl)
        or      a
        jr      z, sfx_record_missing
        inc     hl                      ; -> sfx record {page,off,len}
        or      a
        ret
sfx_record_missing:
        scf
        ret

skip_a_times_3:
        ld      e, a
        ld      d, #0
        add     hl, de
        add     hl, de
        add     hl, de
        ret

skip_a_times_5:
        ld      e, a
        ld      d, #0
        add     hl, de
        add     hl, de
        add     hl, de
        add     hl, de
        add     hl, de
        ret

skip_a_times_6:
        ld      e, a
        ld      d, #0
        add     hl, de
        add     hl, de
        add     hl, de
        add     hl, de
        add     hl, de
        add     hl, de
        ret

; BC = sample length. Tail = round_up_128(len) + 256 - len.
compute_silence_tail_bc:
        ld      h, b
        ld      l, c
        ld      de, #127
        add     hl, de
        ld      a, l
        and     #0x80
        ld      l, a
        ld      de, #256
        add     hl, de                  ; rounded + one FIFO
        or      a
        sbc     hl, bc
        ret

map_logical_page_win3:
        call    logical_to_phys_a
        out     (#SLOT3), a
        ret

logical_to_phys_a:
        ld      e, a
        ld      d, #0
        ld      hl, #EVO_PAGE_TABLE
        add     hl, de
        ld      a, (hl)
        ret

cbl_flush_256:
        ld      c, #0x4F
        ld      b, #0
        ld      a, #0x80
        ld      d, #0
1$:
        out     (c), a
        dec     d
        jr      nz, 1$
        ret

; Output exactly 128 bytes to CBL_DATA. Sample bytes stream while
; _cbl_sample_remaining>0, then #80 silence consumes _cbl_tail_remaining.
; The source pointer stays in HL and the remaining count in DE for the whole
; burst, the port in BC (B must stay 0 -- it is the I/O addr-hi byte), and the
; 128 burst counter in the alternate accumulator A'. RAM state is written back
; once per burst (and on the rare 16K page-cross) instead of the old per-byte
; load+store of _cbl_sample_remaining/_cbl_sample_ptr.
cbl_stream_128:
        ld      bc, #0x004F             ; B=0 (addr-hi), C=#4F (CBL_DATA)
        ld      hl, (_cbl_sample_ptr)
        ld      de, (_cbl_sample_remaining)
        ld      a, #128
        ex      af, af'                 ; A' = burst byte counter
stream_loop:
        ld      a, d
        or      e
        jr      z, stream_silence_run   ; sample drained -> rest of burst silent

        ld      a, (hl)
        out     (c), a
        inc     hl
        dec     de
        ld      a, h
        or      a
        jr      z, stream_page_cross    ; HL wrapped past #FFFF -> next page
stream_next:
        ex      af, af'                 ; A = counter
        dec     a
        jr      z, stream_done          ; burst filled (test before swap back)
        ex      af, af'                 ; A' = counter, A = stale (reloaded next)
        jr      stream_loop
stream_done:
        ld      (_cbl_sample_ptr), hl
        ld      (_cbl_sample_remaining), de
        ret

stream_page_cross:
        push    de                      ; logical_to_phys_a clobbers DE/HL
        ld      hl, #_cbl_logical_page
        inc     (hl)
        ld      a, (hl)
        call    map_logical_page_win3
        pop     de
        ld      hl, #0xC000
        jr      stream_next

stream_silence_run:
        ld      (_cbl_sample_remaining), de   ; DE==0 here: persist drained sample
        ld      de, (_cbl_tail_remaining)     ; reuse DE as the silence counter
        ld      a, #0x80
silence_loop:
        out     (c), a
        dec     de
        ex      af, af'                 ; A = counter
        dec     a
        jr      z, silence_done
        ex      af, af'                 ; A' = counter, A = #0x80 (kept in A')
        jr      silence_loop
silence_done:
        ld      (_cbl_tail_remaining), de
        ret

_sound_tick::
        ld      a, (_music_active)
        or      a
        jr      z, 1$
        call    music_call_play
1$:
        ld      a, (_sfx_active)
        or      a
        ret     z
        jp      sfx_call_frame

music_call_init:
        ld      hl, #0xC000
        jr      music_call_hl

music_call_play:
        ld      hl, #0xC005
        jr      music_call_hl

music_call_mute:
        ld      hl, #0xC008

music_call_hl:
        di
        in      a, (#SLOT3)
        ld      (_music_saved_win3), a
        ld      a, (_music_phys_page)
        out     (#SLOT3), a
        push    ix
        push    iy
        call    music_do_call
        pop     iy
        pop     ix
        ld      a, (_music_saved_win3)
        out     (#SLOT3), a
        ret

music_do_call:
        jp      (hl)

sfx_call_init:
        ld      hl, #0xC000
        jr      sfx_call_hl

sfx_call_play:
        ld      hl, #0xC003
        jr      sfx_call_hl_with_args

sfx_call_frame:
        ld      hl, #0xC006

sfx_call_hl:
        di
        in      a, (#SLOT3)
        ld      (_sfx_saved_win3), a
        ld      a, (_sfx_phys_page)
        out     (#SLOT3), a
        push    ix
        push    iy
        call    sfx_do_call
        pop     iy
        pop     ix
        ld      a, (_sfx_saved_win3)
        out     (#SLOT3), a
        ret

sfx_call_hl_with_args:
        di
        in      a, (#SLOT3)
        ld      (_sfx_saved_win3), a
        ld      a, (_sfx_phys_page)
        out     (#SLOT3), a
        push    ix
        push    iy
        ld      a, (_sfx_vol)
        ld      c, a
        ld      a, (_sfx_id)
        call    sfx_do_call
        pop     iy
        pop     ix
        ld      a, (_sfx_saved_win3)
        out     (#SLOT3), a
        ret

sfx_do_call:
        jp      (hl)

        .area   _SDKDATA
_music_active:
        .db     0
_music_phys_page:
        .db     0
_music_saved_win3:
        .db     0
_sfx_id:
        .db     0
_sfx_vol:
        .db     0
_sfx_active:
        .db     0
_sfx_initialized:
        .db     0
_sfx_phys_page:
        .db     0
_sfx_saved_win3:
        .db     0
_cbl_logical_page:
        .db     0
_cbl_sample_ptr:
        .dw     0
_cbl_sample_remaining:
        .dw     0
_cbl_tail_remaining:
        .dw     0
_cbl_saved_win3:
        .db     0
_cbl_ctrl:
        .db     0
_cbl_active:                            ; 1 while a sample is streaming (IRQ-driven)
        .db     0
_cbl_irq_saved_win3:                    ; WIN3 saved/restored inside the CBL IRQ
        .db     0
