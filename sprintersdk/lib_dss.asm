; =========================================================================
;  lib_dss.asm -- blocking DSS file I/O into paged memory  [opt-in FILEIO=1]
; =========================================================================
;  Sprinter-only extension (EvoSDK has no file API). All of this is assembled
;  ONLY when FILEIO=1; with FILEIO=0 the module is empty and adds zero bytes,
;  so existing builds stay byte-identical.
;
;  WHY A TRAMPOLINE (HW_NOTES; refs: spevosdk loader.asm exit trampoline,
;  sdcc-sprinter-sdk/lib/win0). The game runs CACHE on: WIN0 = SRAM holds the hot
;  SDK code AND the stack (#2000-#23FF). DSS lives behind CACHE off (WIN0 = DSS
;  BIOS), so RST #10 only reaches DSS with CACHE off -- but that ERASES WIN0
;  (SRAM code + stack) for the duration. So a DSS call must:
;    * run its inner code from a window that is NOT WIN0 (we use a dedicated DRAM
;      page mapped into WIN2 -- handed off by the loader),
;    * move SP onto a DRAM stack in that page,
;    * DI (the IM2 vector table is in the vanished SRAM); switch IM 1 + EI so DSS's
;      own interrupt (disk polling) works during the RST,
;    * after the call: DI, CACHE on (WIN0=SRAM back), IM 2, restore SP/WIN1, EI.
;  The whole call is therefore BLOCKING: music/sound/frame are frozen for it.
;
;  WIN2 is the program's code chunk2 normally; we map the trampoline page over it
;  for the call and restore chunk2 from an SRAM stub afterwards (you cannot switch
;  the window you execute from, so the final WIN2 restore + return runs from SRAM).
;
;  DSS call convention (verified Estex-DSS DSS/API + dss_equ.inc): RST #10, fn in
;  C, args in A/B/HL/DE/IX; CF=1 = error (code in A). READ/WRITE return the byte
;  count in DE (Read.asm .ROV6: SBC HL,start; EX DE,HL; RET).
; =========================================================================

        .module lib_dss

        .if FILEIO
        .globl  _file_open
        .globl  _file_create
        .globl  _file_close
        .globl  _file_read
        .globl  _file_write
        .globl  _mem_alloc
        .globl  _mem_pages
        .globl  _page_peek
        .globl  _page_poke
        .globl  _page_read
        .globl  _page_write
        .globl  _dss_install_tramp      ; called by runtime_init

        .area   _SDK

; ---- ports / cache (loader.asm) ----
SLOT0       = 0x82                      ; WIN0 page register
SLOT1       = 0xA2                      ; WIN1
SLOT2       = 0xC2                      ; WIN2
SLOT3       = 0xE2                      ; WIN3
CACHE_PAGE  = 0x8F
CACHE_ON    = 0xFB                      ; IN A,(#FB) -> WIN0=SRAM
CACHE_OFF   = 0x7B                      ; IN A,(#7B) -> WIN0=DSS BIOS

; ---- DSS / BIOS functions ----
DSS_CREATE  = 0x0A
DSS_OPEN    = 0x11
DSS_CLOSE   = 0x12
DSS_READ    = 0x13
DSS_WRITE   = 0x14
DSS_GETMEM  = 0x3D
DSS_FREEMEM = 0x3E
BIOS_GETMEMBLKPAGES = 0xC5

; ---- trampoline page WIN2 layout (#8000-#BFFF). The body is copied here by
;      _dss_install_tramp; the request/result scratch is read/written by both the
;      SRAM wrappers (while WIN2=tramp page) and the body. ----
TRAMP_ORG   = 0x8000                    ; body entry (in WIN2)
TRAMP_STACK = 0xBCFE                    ; DRAM stack top (below the scratch)
TS_FN       = 0xBD00                    ; request: function code (C)
TS_A        = 0xBD01                    ; request: A
TS_B        = 0xBD02                    ; request: B
TS_HL       = 0xBD03                    ; request: HL (u16)
TS_DE       = 0xBD05                    ; request: DE (u16)
TS_IX       = 0xBD07                    ; request: IX (u16)
TS_WIN1     = 0xBD09                    ; request: phys page -> WIN1 (0 = leave WIN1)
TS_RST      = 0xBD0A                    ; request: 0 = RST #10 (DSS), 1 = RST #08 (BIOS)
TS_RA       = 0xBD0B                    ; result: A          (contiguous block ->
TS_RB       = 0xBD0C                    ; result: B           gate_call copies these
TS_RDE      = 0xBD0D                    ; result: DE (u16)    5 bytes to g_res)
TS_RCF      = 0xBD0F                    ; result: CF (0/1)
TS_SP       = 0xBD10                    ; saved SRAM SP
TS_W1       = 0xBD12                    ; saved WIN1 page
TS_NAME     = 0xBD20                    ; bounced ASCIIZ filename / page-list buffer
NAME_MAX    = 96                        ; filename path <=95+NUL; page list <=96 pages

; SRAM handoff: physical page of the trampoline DRAM block, written by the loader
; at a FIXED SRAM address (the loader is linked standalone and cannot see lib_dss
; symbols, so the handoff goes through this absolute slot -- like the EVO_SAVED_*
; exit slots at #1AC8..#1ACD). 0 = no page -> file I/O inert.
_dss_tramp_page = 0x1ACE

; =========================================================================
;  _dss_install_tramp(): copy the straight-line trampoline body into the loader-
;  provided DRAM page (mapped transiently into WIN1) so it lives at WIN2:#8000.
;  Called once from runtime_init AFTER the page table / handoff is in place.
; =========================================================================
_dss_install_tramp::
        ld      a, (_dss_tramp_page)
        or      a
        ret     z                       ; no page handed off -> file I/O unavailable
        di
        in      a, (#SLOT1)
        ld      (_dss_saved_win1), a
        ld      a, (_dss_tramp_page)
        out     (#SLOT1), a             ; WIN1 = trampoline DRAM page
        ld      hl, #tramp_body
        ld      de, #0x4000             ; WIN1 view of the page, offset 0 == #8000 view
        ld      bc, #tramp_body_end - tramp_body
        ldir
        ld      a, (_dss_saved_win1)
        out     (#SLOT1), a
        ei
        ret

; =========================================================================
;  dss_gate: drive ONE DSS/BIOS call through the trampoline. Request fields are
;  already written into the tramp-page scratch (TS_*). Returns nothing; result is
;  in TS_RA/TS_RDE/TS_RCF (read by the caller after restore). Runs from SRAM,
;  maps the tramp page into WIN2, jumps into the body, and is resumed at
;  dss_gate_return after the body restores SRAM/CACHE.
;  In: nothing (scratch pre-filled, WIN2 already = tramp page). DI on entry.
; =========================================================================
; The body is straight-line + only relative (jr) internal branches, so it is
; position-independent at #8000. Internal absolute jp/call are forbidden EXCEPT the
; final jp to the SRAM resume stub (valid once CACHE is back on).
tramp_body:
        ld      (TS_SP), sp             ; save SRAM SP (WIN0=SRAM still mapped here)
        ld      sp, #TRAMP_STACK        ; SP -> WIN2 DRAM stack
        in      a, (#SLOT1)
        ld      (TS_W1), a              ; save caller WIN1
        ld      a, (TS_WIN1)
        or      a
        jr      z, 1$
        out     (#SLOT1), a             ; WIN1 = buffer page for the DSS read/write
1$:
        ; --- enter DSS context: CACHE off, IM 1, EI (disk polling) ---
        di
        in      a, (#CACHE_OFF)         ; WIN0 = DSS BIOS (SRAM gone)
        im      1
        ; load DSS argument registers from the scratch
        ld      ix, (TS_IX)
        ld      hl, (TS_HL)
        ld      de, (TS_DE)
        ld      a, (TS_B)
        ld      b, a
        ld      a, (TS_FN)
        ld      c, a
        ld      iy, #0                  ; harmless default
        ; Decide RST #10 (DSS) vs RST #08 (BIOS) BEFORE loading A: 'or a' sets Z,
        ; and the following 'ld a' does NOT touch flags, so Z survives to the jr.
        ld      a, (TS_RST)
        or      a
        ld      a, (TS_A)               ; A = primary arg (flags from 'or a' preserved)
        jr      nz, 2$
        ei
        rst     #0x10                   ; DSS call
        jr      3$
2$:
        ei
        rst     #0x08                   ; BIOS call
3$:
        di
        ; capture result (CF, A, B, DE) into the scratch. B carries the count for
        ; BIOS EMM_LIST (#C5); A/DE carry handles / byte counts for DSS calls.
        push    af                      ; F has CF
        ld      (TS_RDE), de
        ld      a, b
        ld      (TS_RB), a
        pop     af
        ld      (TS_RA), a
        ld      a, #0
        jr      nc, 4$
        ld      a, #1
4$:
        ld      (TS_RCF), a
        ; --- leave DSS context: CACHE on (WIN0=SRAM), IM 2 ---
        ld      a, (TS_W1)
        out     (#SLOT1), a             ; restore caller WIN1
        xor     a
        out     (#CACHE_PAGE), a        ; ROM_RG = 0 (loader CACHE-on order)
        in      a, (#CACHE_ON)          ; WIN0 = SRAM back
        im      2
        ld      sp, (TS_SP)             ; SP -> SRAM stack (WIN0 SRAM is back)
        jp      dss_gate_return         ; absolute SRAM addr -- valid now
tramp_body_end:

; =========================================================================
;  SRAM-side gate entry. Pre: DI, scratch (TS_*) filled, but WIN2 still = caller
;  chunk2. Saves chunk2, maps the tramp page into WIN2, jumps into the body.
;  Resumes at dss_gate_return (body jumps back here after CACHE on).
; =========================================================================
dss_gate:
        in      a, (#SLOT2)
        ld      (_dss_saved_win2), a    ; save program chunk2
        ld      a, (_dss_tramp_page)
        out     (#SLOT2), a             ; WIN2 = trampoline page
        jp      TRAMP_ORG               ; enter body (in WIN2 #8000)
dss_gate_return:
        ; WIN0=SRAM, WIN2 still = tramp page; result is in the scratch.
        ld      a, (_dss_saved_win2)
        out     (#SLOT2), a             ; restore program chunk2
        ret

; =========================================================================
;  gate_call: SRAM helper -- caller has put the request bytes in g_req (SRAM);
;  copy them to the tramp scratch (needs WIN2=tramp page first), run the gate,
;  copy the result back to g_res (SRAM). DI/EI around the whole thing.
;  This keeps the C wrappers from touching WIN2 directly.
; =========================================================================
gate_call:
        ld      a, (_dss_tramp_page)
        or      a
        jr      nz, gc_go
        ; no trampoline page handed off -> report error, never touch WIN2 (mapping
        ; physical page 0 would crash). File I/O is simply unavailable.
        ld      a, #1
        ld      (g_res_cf), a
        xor     a
        ld      (g_res_a), a
        ld      (g_res_de), a
        ld      (g_res_de + 1), a
        ret
gc_go:
        di
        in      a, (#SLOT2)
        ld      (_dss_saved_win2), a
        ld      a, (_dss_tramp_page)
        out     (#SLOT2), a             ; WIN2 = tramp page (scratch addressable)
        ld      hl, #g_req              ; copy SRAM request -> tramp scratch
        ld      de, #TS_FN
        ld      bc, #g_req_len
        ldir
        ; also bounce the filename (g_name) -> TS_NAME (in case this is open/create)
        ld      hl, #g_name
        ld      de, #TS_NAME
        ld      bc, #NAME_MAX
        ldir
        ; restore chunk2 (gate re-maps it itself); run the gate
        ld      a, (_dss_saved_win2)
        out     (#SLOT2), a
        call    dss_gate
        ; gate restored WIN2=chunk2; copy result + the page-list buffer out of the
        ; tramp scratch (mem_pages reads g_name; everyone reads g_res).
        in      a, (#SLOT2)
        ld      (_dss_saved_win2), a
        ld      a, (_dss_tramp_page)
        out     (#SLOT2), a
        ld      hl, #TS_RA
        ld      de, #g_res
        ld      bc, #g_res_len
        ldir
        ld      hl, #TS_NAME
        ld      de, #g_name
        ld      bc, #NAME_MAX
        ldir
        ld      a, (_dss_saved_win2)
        out     (#SLOT2), a
        ei
        ret

; -------------------------------------------------------------------------
;  Public C wrappers. SDCC: args on stack, return u16 in HL. Each fills g_req /
;  g_name, calls gate_call, maps g_res -> return value.
; -------------------------------------------------------------------------

; i16 file_open(const char *name, u8 mode)
_file_open::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = name ptr
        inc     hl
        ld      a, (hl)                 ; mode
        ld      (gr_a), a               ; A = mode
        ex      de, hl
        call    copy_name               ; HL=name -> g_name (ASCIIZ)
        ld      a, #DSS_OPEN
        ld      (gr_fn), a
        ld      hl, #TS_NAME            ; HL arg = bounced name in tramp scratch
        ld      (gr_hl), hl
        xor     a
        ld      (gr_win1), a
        ld      (gr_rst), a
        call    gate_call
        jp      ret_handle              ; CF -> -1 else A=handle

; i16 file_create(const char *name)
_file_create::
        ld      hl, #2
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ex      de, hl
        call    copy_name
        ld      a, #0x20                ; normal-file attribute
        ld      (gr_a), a
        ld      a, #DSS_CREATE
        ld      (gr_fn), a
        ld      hl, #TS_NAME
        ld      (gr_hl), hl
        xor     a
        ld      (gr_win1), a
        ld      (gr_rst), a
        call    gate_call
        jp      ret_handle

; void file_close(u8 h)
_file_close::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (gr_a), a
        ld      a, #DSS_CLOSE
        ld      (gr_fn), a
        call    clear_buf_req
        call    gate_call
        ret

; i16 file_read(u8 h, u8 page, u16 off, u16 len) -- read <=16K into page:off
_file_read::
        ld      a, #DSS_READ
        jr      rw_common
; i16 file_write(u8 h, u8 page, u16 off, u16 len)
_file_write::
        ld      a, #DSS_WRITE
rw_common:
        ld      (gr_fn), a
        ld      hl, #2
        add     hl, sp                  ; args at SP+2 (ret addr at SP+0; no IX push):
        ld      a, (hl)                 ; h (handle)  SP+2
        ld      (gr_a), a
        inc     hl
        ld      a, (hl)                 ; page
        ld      (gr_win1), a            ; map into WIN1
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; off
        ex      de, hl
        ld      de, #0x4000
        add     hl, de                  ; HL = #4000 + off (WIN1 view)
        ld      (gr_hl), hl
        ld      hl, #6
        add     hl, sp
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; len
        ld      (gr_de), de
        xor     a
        ld      (gr_rst), a
        call    gate_call
        ; READ returns the actual byte count in DE (Read.asm .ROV6). WRITE does NOT
        ; report a reliable count in DE -- sdcc-sprinter-sdk's dss_write discards it
        ; and returns the REQUESTED length on success. Mirror that: on CF=0, READ ->
        ; g_res_de, WRITE -> the requested length (gr_de, untouched by gate_call).
        ld      a, (g_res_cf)
        or      a
        jr      nz, rw_err
        ld      a, (gr_fn)
        cp      #DSS_WRITE
        jr      z, rw_written
        ld      hl, (g_res_de)          ; READ: actual bytes read
        ret
rw_written:
        ld      hl, (gr_de)             ; WRITE ok: requested length
        ret
rw_err:
        ld      hl, #0xFFFF
        ret

; u8 mem_alloc(u8 pages)  -> DSS block id (0xFF on error)
_mem_alloc::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)
        ld      (gr_b), a               ; B = pages
        ld      a, #DSS_GETMEM
        ld      (gr_fn), a
        xor     a
        ld      (gr_win1), a
        ld      (gr_rst), a
        call    gate_call
        ld      a, (g_res_cf)
        or      a
        jr      nz, 1$
        ld      a, (g_res_a)            ; block id
        ld      l, a
        ld      h, #0
        ret
1$:
        ld      hl, #0x00FF
        ret

; u8 mem_pages(u8 block, u8 *dst) -> page count; dst gets the physical page list
;   dst is bounced through the tramp scratch then copied back to the C buffer.
_mem_pages::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; block id
        ld      (gr_a), a
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; DE = dst (C buffer)
        ld      (mp_dst), de
        ld      hl, #TS_NAME            ; reuse the name buffer as the page list out
        ld      (gr_hl), hl
        ld      a, #BIOS_GETMEMBLKPAGES
        ld      (gr_fn), a
        ld      a, #1
        ld      (gr_rst), a             ; RST #08 (BIOS)
        xor     a
        ld      (gr_win1), a
        call    gate_call
        ; BIOS EMM_LIST returns the page count in B (now captured in g_res_b) and
        ; writes the page list into the buffer (TS_NAME, mirrored to g_name by
        ; gate_call). Copy the list to the C buffer and return the count.
        ld      a, (g_res_cf)
        or      a
        jr      nz, 1$
        ld      a, (g_res_b)            ; page count
        ld      c, a
        ld      b, #0
        or      a
        jr      z, 1$                   ; 0 pages -> nothing to copy
        ld      hl, #g_name
        ld      de, (mp_dst)
        ldir                            ; copy exactly 'count' pages -> C buffer
1$:
        ld      a, (g_res_b)
        ld      l, a
        ld      h, #0
        ret

; -------------------------------------------------------------------------
;  Paged-memory accessors (no DSS -- pure window paging, DI + save/restore WIN1).
;  The C buffer (src/dst) must NOT live in WIN1 (#4000-#7FFF). Borrow WIN1 for the
;  paged page; the C side is in WIN0/WIN2/WIN3.
; -------------------------------------------------------------------------

; u8 page_peek(u8 page, u16 off)
_page_peek::
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; page
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; off
        di
        in      a, (#SLOT1)
        ld      (_dss_saved_win1), a
        ld      hl, #2
        add     hl, sp
        ld      a, (hl)                 ; page (reload)
        out     (#SLOT1), a
        ex      de, hl
        ld      de, #0x4000
        add     hl, de                  ; #4000 + off
        ld      l, (hl)
        ld      a, (_dss_saved_win1)
        out     (#SLOT1), a
        ei
        ld      h, #0
        ret

; void page_poke(u8 page, u16 off, u8 val)
_page_poke::
        ld      hl, #2
        add     hl, sp
        ld      c, (hl)                 ; page
        inc     hl
        ld      e, (hl)
        inc     hl
        ld      d, (hl)                 ; off
        inc     hl
        ld      b, (hl)                 ; val
        di
        in      a, (#SLOT1)
        ld      (_dss_saved_win1), a
        ld      a, c
        out     (#SLOT1), a
        ex      de, hl
        ld      de, #0x4000
        add     hl, de
        ld      (hl), b
        ld      a, (_dss_saved_win1)
        out     (#SLOT1), a
        ei
        ret

; void page_read(u8 page, u16 off, void *dst, u16 len)  -- paged -> C buffer
_page_read::
        push    ix
        ld      ix, #4
        add     ix, sp
        di
        in      a, (#SLOT1)
        ld      (_dss_saved_win1), a
        ld      a, 0 (ix)               ; page
        out     (#SLOT1), a
        ld      l, 1 (ix)
        ld      h, 2 (ix)               ; off
        ld      de, #0x4000
        add     hl, de                  ; HL = src = #4000+off (WIN1)
        ld      e, 3 (ix)
        ld      d, 4 (ix)               ; DE = dst (C buffer)
        ld      c, 5 (ix)
        ld      b, 6 (ix)               ; BC = len
        ldir
        ld      a, (_dss_saved_win1)
        out     (#SLOT1), a
        ei
        pop     ix
        ret

; void page_write(u8 page, u16 off, const void *src, u16 len)  -- C buffer -> paged
_page_write::
        push    ix
        ld      ix, #4
        add     ix, sp
        di
        in      a, (#SLOT1)
        ld      (_dss_saved_win1), a
        ld      a, 0 (ix)
        out     (#SLOT1), a
        ld      e, 1 (ix)
        ld      d, 2 (ix)               ; off
        push    de
        ld      l, 3 (ix)
        ld      h, 4 (ix)               ; HL = src (C buffer)
        pop     de
        ex      de, hl                  ; HL=off..., DE=src? fix below
        ; HL = off, DE = src -> dest = #4000+off, src = DE
        ld      bc, #0x4000
        add     hl, bc                  ; HL = #4000+off (dest)
        ex      de, hl                  ; DE = dest, HL = src
        ld      c, 5 (ix)
        ld      b, 6 (ix)               ; BC = len
        ldir
        ld      a, (_dss_saved_win1)
        out     (#SLOT1), a
        ei
        pop     ix
        ret

; -------------------------------------------------------------------------
;  Small SRAM helpers
; -------------------------------------------------------------------------
; copy_name: HL = ASCIIZ source -> g_name (max NAME_MAX-1 + NUL). Caller's windows
;   are all normal here (no switch yet), so the source pointer reads fine.
copy_name:
        ld      de, #g_name
        ld      b, #NAME_MAX - 1
1$:
        ld      a, (hl)
        ld      (de), a
        or      a
        ret     z
        inc     hl
        inc     de
        djnz    1$
        xor     a
        ld      (de), a
        ret

clear_buf_req:
        xor     a
        ld      (gr_win1), a
        ld      (gr_rst), a
        ret

; ret_handle: g_res -> i16 (A=handle if CF=0 else -1)
ret_handle:
        ld      a, (g_res_cf)
        or      a
        jr      nz, 1$
        ld      a, (g_res_a)
        ld      l, a
        ld      h, #0
        ret
1$:
        ld      hl, #0xFFFF
        ret

; ret_count: g_res -> i16 (DE=count if CF=0 else -1)
ret_count:
        ld      a, (g_res_cf)
        or      a
        jr      nz, 1$
        ld      hl, (g_res_de)
        ret
1$:
        ld      hl, #0xFFFF
        ret

; -------------------------------------------------------------------------
        .area   _SDKDATA
_dss_saved_win1:
        .db     0
_dss_saved_win2:
        .db     0
mp_dst:
        .dw     0

; request block (SRAM staging; copied to the tramp scratch by gate_call). The
; field order MUST match TS_FN..TS_RST contiguous layout.
g_req:
gr_fn:  .db     0
gr_a:   .db     0
gr_b:   .db     0
gr_hl:  .dw     0
gr_de:  .dw     0
gr_ix:  .dw     0
gr_win1:.db     0
gr_rst: .db     0
g_req_end:
g_req_len = g_req_end - g_req

; result block (mirrors TS_RA..TS_RCF, contiguous)
g_res:
g_res_a: .db    0
g_res_b: .db    0
g_res_de:.dw    0
g_res_cf:.db    0
g_res_end:
g_res_len = g_res_end - g_res

g_name: .ds     NAME_MAX                ; bounced filename (<=95+NUL) / page-list (<=96)
        .endif
