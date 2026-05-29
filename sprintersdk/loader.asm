; =========================================================================
;  loader.asm -- Sprinter DSS PRELOAD loader for the EvoSDK C image.
; =========================================================================
;  Linked standalone at LOADER_ORG (#8100, WIN2) and emitted verbatim into the
;  monoblock EXE by tools/dss_exe.py. DSS reads only this loader (LOADER field
;  in the EXE header) to #8100, jumps here with the EXE file left OPEN, FM (file
;  handle) at (IX-3), file position right after the loader bytes.
;
;  WHY WIN2: DSS/BIOS use WIN0 (system) and WIN1 (scratch) -- e.g. DSS SetVMod
;  -> BIOS WIN_OPEN clobbers WIN1. The canonical DSS program load address is
;  #8100/WIN2 (manual 07_disk/05_examples, 10_tutorials/04). A loader at #4100/
;  WIN1 (with its stack there) is destroyed by the first SetVMod. So the loader
;  lives in WIN2 and STAGES all page loads through WIN1 (free after SetVMod).
;
;  Memory discipline (HW_NOTES §9.2, §11.3; first-source: Estex-DSS +
;  evosdk_libs/sprinter). The game runs CACHE on (WIN0=SRAM = hot SDK code);
;  this loader runs in WIN2 (DRAM) with CACHE off (WIN0=DSS BIOS) so RST #10
;  reaches DSS. It never maps anything into WIN2 under itself.
;
;  Sequence:
;    1. Save FM + original video mode (DSS GetVMod).
;    2. Read the 16-byte body mini-header (K code chunks, M asset pages,
;       flags, meta_size, hot_size, entry). If flags.bit0 is set, read the
;       (K+M) word payload-size table; 0x4000=raw page, smaller=HRUST .hst.
;    3. DSS SetVMod #81 (320x256x8) on both buffer pages -- done here while
;       WIN0=DSS, so the SRAM runtime never has to call DSS for video.
;    4. Allocate one DSS block for K code chunks, ask BIOS for its physical page
;       list, then read raw 16 KB into each page (or read + HRUST-depack packed
;       payloads). chunk0 -> SRAM(hot), 1->WIN1,2->WIN2,3->WIN3.
;    5. Read EVP1 metadata + M asset pages; record asset pages in the table.
;    6. Write the SDK tables (page table #1A00, saved vmode #1AC8) into chunk0
;       via the WIN1 staging view (#4000+offset), before chunk0 is LDIR'd.
;    7. CACHE on (OUT #8F,0 / IN #FB); LDIR chunk0 (mapped to WIN1) into WIN0
;       SRAM at #0000. Map WIN1=chunk1, WIN3=chunk3 (the loader can't map its
;       own WIN2 -- crt0 does that).
;    8. LD A,<WIN2 page>; JP entry (#2400). crt0 _entry does OUT (#C2),A.
;
;  No relocation: instruction fetch stays in WIN2 (this code) until JP entry,
;  which lands in WIN0 SRAM (the hot SDK / crt0). Runtime verification is on
;  the emulator/HW (architect side).
; =========================================================================

        .module loader
        .area   _CODE

; ---- ports (SP2000.inc) ----
SLOT0       =       0x82            ; WIN0 page register
SLOT1       =       0xA2            ; WIN1 page register
SLOT2       =       0xC2            ; WIN2 page register
SLOT3       =       0xE2            ; WIN3 page register
CACHE_PAGE  =       0x8F            ; OUT (#8F),0 -> ROM_RG=0 (cache page 0)
CACHE_ON    =       0xFB            ; IN A,(#FB) -> CASH_ON=1, WIN0=SRAM
CACHE_OFF   =       0x7B            ; IN A,(#7B) -> CASH_ON=0, WIN0=DSS BIOS

; ---- DSS functions (dss_equ.inc; RST #10, fn in C) ----
DSS_READ    =       0x13
DSS_GETMEM  =       0x3D
DSS_SETVMOD =       0x50
DSS_GETVMOD =       0x51
DSS_EXIT    =       0x41
DSS_PUTCHAR =       0x5B            ; print char in A to the DSS console (text mode)

BIOS_GETMEMBLKPAGES = 0xC5

VIDEO_MODE  =       0x81            ; 320x256x8bpp

; ---- loader scratch, fixed high in the loader's own WIN2 page (#8000-#BFFF) ----
;      (above the loader code; not in _DATA/_BSS, so the binary == pure code)
l_fm        =       0xBC00          ; file handle
l_vmode     =       0xBC02          ; original DSS video mode
l_K         =       0xBC03          ; code chunk count
l_M         =       0xBC04          ; asset page count
l_flags     =       0xBC05          ; mini-header flags; bit0 = packed pages
l_meta      =       0xBC06          ; word: EVP1 meta byte count
l_hot       =       0xBC08          ; word: bytes of chunk0 to copy into SRAM
l_entry     =       0xBC0A          ; word: game entry
l_page_tmp  =       0xBC0C          ; scratch: destination page being loaded
l_dss_w0    =       0xBC0D          ; original DSS WIN0 phys page (for exit)
l_dss_w1    =       0xBC0E          ; original DSS WIN1 phys page (for exit)
l_dss_w3    =       0xBC0F          ; original DSS WIN3 phys page (for exit)
l_pages     =       0xBC10          ; 4 bytes: code chunk physical pages
l_assets    =       0xBC20          ; up to 200 bytes: asset physical pages (-> #BCE7, below SP #BFFF)
l_hdr       =       0xBC80          ; 16-byte mini-header read buffer
l_sizes     =       0xBCA0          ; up to 68 words: packed payload sizes
l_hrust_sp  =       0xBD40          ; saved loader SP while HRUST uses SP as input
l_hrust_stack_top =  0xBD80          ; small private stack for the HRUST depacker
LOADER_SP   =       0xBFFF          ; loader stack top (own WIN2 page)

MINI_FLAG_PACKED =  0x01

; ---- SDK runtime tables live in the SDK SRAM region (mirror of EvoSDK
;      #E000-#FFFF). The loader writes them into chunk0 (which it then LDIRs into
;      SRAM) through the WIN1 staging view: while chunk0 is mapped to WIN1, its
;      offset X is reachable at #4000+X. MUST match lib_startup.asm/lib_tiles.asm.
EVO_PAGE_TABLE   = 0x1A00           ; SRAM: asset phys page table, 200 entries (#1A00-#1AC7)
EVO_SAVED_VMODE  = 0x1AC8           ; SRAM: original DSS video mode (for exit)
EVO_SAVED_W0     = 0x1AC9           ; SRAM: original DSS WIN0 phys page (for exit)
EVO_SAVED_W1     = 0x1ACA           ; SRAM: original DSS WIN1 phys page (for exit)
EVO_SAVED_W3     = 0x1ACB           ; SRAM: original DSS WIN3 phys page (for exit)
EVO_META         = 0x1B00           ; SRAM: EVP1 header+metadata copy
STAGE            = 0x4000           ; WIN1 view base of a page during staging
STAGE_PAGE_TABLE = STAGE + EVO_PAGE_TABLE
STAGE_SAVED_VMODE = STAGE + EVO_SAVED_VMODE
STAGE_SAVED_W0   = STAGE + EVO_SAVED_W0
STAGE_SAVED_W1   = STAGE + EVO_SAVED_W1
STAGE_SAVED_W3   = STAGE + EVO_SAVED_W3
STAGE_META       = STAGE + EVO_META

; =========================================================================
_loader_entry::
        di
        ld      sp, #LOADER_SP

        ; --- 1. FM = (IX-3); save original video mode (for exit) ---
        ld      a, -3(ix)
        ld      (l_fm), a

        push    ix
        ld      c, #DSS_GETVMOD
        rst     #0x10                   ; A = current video mode
        pop     ix
        ld      (l_vmode), a

        ; --- 1b. Save the DSS page layout (WIN0/WIN1/WIN3) before we clobber it,
        ;        so the exit trampoline can restore it. WIN2 is our own window.
        ;        Page registers are readable (cf. flappybird IN A,(EmmWin.Px)). ---
        in      a, (SLOT0)
        ld      (l_dss_w0), a
        in      a, (SLOT1)
        ld      (l_dss_w1), a
        in      a, (SLOT3)
        ld      (l_dss_w3), a

        ; --- 2. read the 16-byte mini-header (FP is right after the loader) ---
        ld      hl, #l_hdr
        ld      de, #16
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix
        ld      a, (l_hdr+1)            ; K
        ld      (l_K), a
        ld      a, (l_hdr+2)            ; M
        ld      (l_M), a
        ld      a, (l_hdr+3)            ; flags
        ld      (l_flags), a
        ld      hl, (l_hdr+4)           ; meta_size
        ld      (l_meta), hl
        ld      hl, (l_hdr+6)           ; hot_size
        ld      (l_hot), hl
        ld      hl, (l_hdr+8)           ; entry
        ld      (l_entry), hl

        ; --- 3. Video mode is set AFTER loading (step 6b), not here, so the
        ;        screen stays in DSS text mode during loading (no graphics
        ;        garbage flash) and switches to 320x256x8 only before the jump. ---

        ; --- 3a. Optional packed-body setup: read the (K+M)*2 payload size
        ;        table. Packed pages are depacked in place in the dest window;
        ;        raw pages (size 0x4000) load exactly like uncompressed bodies. ---
        ld      a, (l_flags)
        and     #MINI_FLAG_PACKED
        jr      z, no_packed_table
        ld      a, (l_K)
        ld      b, a
        ld      a, (l_M)
        add     a, b
        ld      l, a
        ld      h, #0
        add     hl, hl                  ; bytes = (K+M)*2
        ex      de, hl
        ld      hl, #l_sizes
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix
no_packed_table:

        ; Show a "loading" message while the screen is still in DSS text mode
        ; (video #81 is set only in step 6b). Each loaded page prints a '.', so
        ; a slow disk read clearly shows progress instead of looking hung.
        ld      hl, #msg_loading
        call    puts

        ; --- 4. load K code chunks (DSS block -> BIOS phys list -> read 16K) ---
        ld      a, (l_K)
        ld      b, a
        ld      hl, #l_pages
        call    getmem_pages
        ld      b, #0                   ; chunk index
load_code_loop:
        ld      a, (l_K)
        cp      b
        jr      z, load_code_done
        push    bc
        ld      c, b
        ld      b, #0
        ld      hl, #l_pages
        add     hl, bc                  ; &l_pages[i]
        ld      a, (hl)                 ; A = physical page
        ld      (hl), a
        ld      (l_page_tmp), a
        ld      a, (l_flags)
        and     #MINI_FLAG_PACKED
        jr      z, load_code_raw
        ld      b, c                    ; restore B = chunk index (C kept it after
        call    payload_size_b          ; the l_pages calc zeroed B)
        ld      a, (l_page_tmp)
        call    read_payload_page
        jr      load_code_next
load_code_raw:
        ld      a, (l_page_tmp)
        out     (SLOT1), a              ; WIN1 = chunk page
        call    read_16k_win1
load_code_next:
        pop     bc
        ld      a, #0x2E                ; progress dot per loaded page ('.')
        call    putc
        inc     b
        jr      load_code_loop
load_code_done:

        ; --- 5. EVP1 metadata -> SDK SRAM region, via chunk0 staged in WIN1 ---
        ld      a, (l_pages+0)
        out     (SLOT1), a              ; WIN1 = chunk0 (hot/SDK page)
        ld      hl, (l_meta)
        ld      a, h
        or      l
        jr      z, load_assets          ; meta_size 0 -> skip
        ld      de, (l_meta)
        ld      hl, #STAGE_META
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix

        ; --- 5b. M asset pages (DSS block -> BIOS phys list -> read 16K) ---
load_assets:
        ld      a, (l_M)
        or      a
        jr      z, asset_done
        ld      b, a
        ld      hl, #l_assets
        call    getmem_pages
        ld      b, #0
asset_loop:
        ld      a, (l_M)
        cp      b
        jr      z, asset_done
        push    bc
        ld      c, b
        ld      b, #0
        ld      hl, #l_assets
        add     hl, bc
        ld      a, (hl)                 ; A = physical page
        ld      (hl), a                 ; l_assets[j] = phys page
        ld      (l_page_tmp), a
        ld      a, (l_flags)
        and     #MINI_FLAG_PACKED
        jr      z, load_asset_raw
        ld      a, (l_K)
        add     a, c                    ; index = K + asset index (C kept it; B was
        ld      b, a                    ; zeroed by the l_assets calc)
        call    payload_size_b
        ld      a, (l_page_tmp)
        call    read_payload_page
        jr      load_asset_next
load_asset_raw:
        ld      a, (l_page_tmp)
        out     (SLOT1), a
        call    read_16k_win1
load_asset_next:
        pop     bc
        ld      a, #0x2E                ; progress dot per loaded page ('.')
        call    putc
        inc     b
        jr      asset_loop
asset_done:

        ; --- 6. fill the SDK tables in chunk0 (staged in WIN1) ---
        ld      a, (l_pages+0)
        out     (SLOT1), a              ; WIN1 = chunk0
        ld      a, (l_vmode)
        ld      (STAGE_SAVED_VMODE), a  ; saved video mode (for exit)
        ld      a, (l_dss_w0)
        ld      (STAGE_SAVED_W0), a     ; saved DSS WIN0 page (for exit)
        ld      a, (l_dss_w1)
        ld      (STAGE_SAVED_W1), a     ; saved DSS WIN1 page (for exit)
        ld      a, (l_dss_w3)
        ld      (STAGE_SAVED_W3), a     ; saved DSS WIN3 page (for exit)
        ld      a, (l_M)
        or      a
        jr      z, tables_done
        ld      c, a
        ld      b, #0
        ld      hl, #l_assets
        ld      de, #STAGE_PAGE_TABLE   ; copy asset phys pages -> page table
        ldir
tables_done:

        ; --- 6b. Set video mode #81 on both screen pages (after loading, so the
        ;        screen stays in text mode during load). Order B=1 then B=0 as
        ;        flappybird ChangeVideoMode. SetVMod clobbers WIN1; step 7 re-maps
        ;        WIN1=chunk0 right after. ---
        push    ix
        ld      a, #VIDEO_MODE
        ld      b, #1
        ld      c, #DSS_SETVMOD
        rst     #0x10
        ld      a, #VIDEO_MODE
        ld      b, #0
        ld      c, #DSS_SETVMOD
        rst     #0x10
        pop     ix

        ; --- 7. CACHE on, LDIR chunk0 (mapped via WIN1) into WIN0 SRAM ---
        ld      a, (l_pages+0)
        out     (SLOT1), a              ; WIN1 = chunk0 (hot) page
        xor     a
        out     (CACHE_PAGE), a         ; ROM_RG = 0
        in      a, (CACHE_ON)           ; WIN0 = SRAM
        ld      hl, #0x4000             ; WIN1 view of chunk0
        ld      de, #0x0000             ; SRAM
        ld      bc, (l_hot)
        ldir

        ; --- map the windows the loader CAN map: WIN1=chunk1, WIN3=chunk3.
        ;     WIN2 (loader's own page) is left for crt0 to map. ---
        ld      a, (l_pages+1)
        out     (SLOT1), a
        ld      a, (l_K)
        cp      #4
        jr      c, no_win3
        ld      a, (l_pages+3)
        out     (SLOT3), a
no_win3:
        ; --- 8. enter game: A = WIN2 page; crt0 _entry does OUT (#C2),A ---
        ld      a, (l_pages+2)
        ld      hl, (l_entry)
        jp      (hl)

; -------------------------------------------------------------------------
; putc: print the char in A to the DSS console (text mode). Preserves every
;   register the load loops rely on (BC carries the page counter, HL/DE the
;   staging pointers), so it is safe to call from inside the loops.
putc:
        push    bc
        push    de
        push    hl
        push    ix
        ld      c, #DSS_PUTCHAR         ; A = char
        rst     #0x10
        pop     ix
        pop     hl
        pop     de
        pop     bc
        ret

; puts: print the null-terminated string at HL. Clobbers A (HL preserved by
;   putc, advanced here). Used for the "loading" banner.
puts:
        ld      a, (hl)
        or      a
        ret     z
        call    putc
        inc     hl
        jr      puts

msg_loading:
        .ascii  "Loading"
        .db     0

msg_nomem:
        .db     0x0D, 0x0A
        .ascii  "Out of memory!"
        .db     0x0D, 0x0A, 0

; -------------------------------------------------------------------------
; getmem_pages: allocate B DSS memory pages and fill HL with physical page list.
;   DSS.GetMem returns a memory block handle. BIOS.GetMemBlkPages resolves that
;   handle into physical page numbers; runtime hot paths use direct OUT
;   (#A2/#C2/#E2), so l_pages/page_table must contain physical pages.
getmem_pages:
        push    ix
        push    hl
        ld      c, #DSS_GETMEM
        rst     #0x10
        jr      c, getmem_pages_error_pophl
        pop     hl
        ld      c, #BIOS_GETMEMBLKPAGES
        rst     #0x08
        jr      c, getmem_pages_error
        pop     ix
        ret
getmem_pages_error_pophl:
        pop     hl
getmem_pages_error:
        pop     ix
        ; --- Out of memory: the EXE needs more free pages than DSS has. We are
        ; still in DSS text mode (video is switched only in step 6b) and CACHE is
        ; off, so report it and return to DSS with a non-zero code instead of
        ; hanging. DSS frees this process's pages on Exit. ---
        ld      hl, #msg_nomem
        call    puts
        ld      b, #0xFF                ; non-zero exit code = error
        ld      c, #DSS_EXIT
        rst     #0x10                   ; DSS.Exit -- does not return
        di
        halt                            ; safety net only if Exit ever returns

; read_16k_win1: Dss.Read 0x4000 bytes from FM into #4000 (WIN1).
read_16k_win1:
        ld      hl, #0x4000
        ld      de, #0x4000
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix
        ret

; payload_size_b: B = payload index -> DE = size table entry.
payload_size_b:
        ld      c, b
        ld      b, #0
        ld      hl, #l_sizes
        add     hl, bc
        add     hl, bc
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ret

; read_payload_page: A = destination physical page, DE = payload size.
;   size 0x4000: raw page read directly into destination via WIN1.
;   otherwise: read .hst into the temp page (WIN1), map destination to WIN3,
;   and HRUST-depack #4000 -> #C000.
read_payload_page:
        push    af
        ld      a, d                    ; size 0 = all-zero page -> zero-fill,
        or      e                       ; no DSS read, no depack (avoids the
        jr      nz, read_payload_sized  ; depacker's degenerate empty-page case)
        pop     af
        out     (SLOT3), a              ; WIN3 = dest page
        jp      zero_fill_win3
read_payload_sized:
        ld      a, d
        cp      #0x40
        jr      nz, read_payload_packed
        ld      a, e
        or      a
        jr      nz, read_payload_packed
        pop     af
        out     (SLOT1), a
        jp      read_16k_win1

; zero_fill_win3: fill the WIN3 destination page (#C000-#FFFF, 16K) with zero.
zero_fill_win3:
        ld      hl, #0xC000
        ld      (hl), #0
        ld      de, #0xC001
        ld      bc, #0x3FFF
        ldir
        ret

read_payload_packed:
        ; In-place depack in the destination window, identical to the proven
        ; sdcc-sprinter-sdk asset_load_pages.c (read .hst to #C000, DePACK
        ; #C000 -> #C000). DE still holds the payload byte count.
        pop     af                      ; A = destination physical page
        out     (SLOT3), a              ; WIN3 = destination page
        ld      hl, #0xC000             ; read the .hst into the dest window
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix
        ld      hl, #0xC000
        ld      de, #0xC000
        call    hrust_depack_loader
        ret

; HRUST .hst depacker from kode/DEPACK / sdcc-sprinter-sdk hrust_depack.s.
; Wrapper contract here: HL=packed source, DE=destination. The depacker uses SP
; as its compressed input pointer, so it runs on a private scratch stack and the
; loader SP is restored before returning.
hrust_depack_loader:
        push    ix
        ld      (l_hrust_sp), sp
        ld      sp, #l_hrust_stack_top
        call    hrust_depack_hl_de
        ld      sp, (l_hrust_sp)
        pop     ix
        ret

hrust_depack_hl_de:
        di
        ld      ix, #0xFFF4
        add     ix, sp
        push    de
        ld      sp, hl
        pop     bc
        ex      de, hl
        pop     bc
        dec     bc
        add     hl, bc
        ex      de, hl
        pop     bc
        dec     bc
        add     hl, bc
        sbc     hl, de
        add     hl, de
        jr      c, hrust_8018
        ld      d, h
        ld      e, l
hrust_8018:
        lddr
        ex      de, hl
        ld      d, 11(ix)
        ld      e, 10(ix)
        ld      sp, hl
        pop     hl
        pop     hl
        pop     hl
        ld      b, #0x06
hrust_8027:
        dec     sp
        pop     af
        ld      6(ix), a
        inc     ix
        djnz    hrust_8027
        exx
        ld      d, #0xBF
        ld      bc, #0x1010
        pop     hl
hrust_8037:
        dec     sp
        pop     af
        exx
hrust_803A:
        ld      (de), a
        inc     de
hrust_803C:
        exx
hrust_803D:
        add     hl, hl
        djnz    hrust_8042
        pop     hl
        ld      b, c
hrust_8042:
        jr      c, hrust_8037
        ld      e, #0x01
hrust_8046:
        ld      a, #0x80
hrust_8048:
        add     hl, hl
        djnz    hrust_804D
        pop     hl
        ld      b, c
hrust_804D:
        rla
        jr      c, hrust_8048
        cp      #0x03
        jr      c, hrust_8059
        add     a, e
        ld      e, a
        xor     c
        jr      nz, hrust_8046
hrust_8059:
        add     a, e
        cp      #0x04
        jr      z, hrust_80B8
        adc     a, #0xFF
        cp      #0x02
        exx
hrust_8063:
        ld      c, a
hrust_8064:
        exx
        ld      a, #0xBF
        jr      c, hrust_807D
hrust_8069:
        add     hl, hl
        djnz    hrust_806E
        pop     hl
        ld      b, c
hrust_806E:
        rla
        jr      c, hrust_8069
        jr      z, hrust_8078
        inc     a
        add     a, d
        jr      nc, hrust_807F
        sub     d
hrust_8078:
        inc     a
        jr      nz, hrust_8087
        ld      a, #0xEF
hrust_807D:
        rrca
        cp      a
hrust_807F:
        add     hl, hl
        djnz    hrust_8084
        pop     hl
        ld      b, c
hrust_8084:
        rla
        jr      c, hrust_807F
hrust_8087:
        exx
        ld      h, #0xFF
        jr      z, hrust_8092
        ld      h, a
        dec     sp
        inc     a
        jr      z, hrust_809D
        pop     af
hrust_8092:
        ld      l, a
        add     hl, de
        ldir
hrust_8096:
        jr      hrust_803C
hrust_8098:
        exx
        rrc     d
        jr      hrust_803D
hrust_809D:
        pop     af
        cp      #0xE0
        jr      c, hrust_8092
        rlca
        xor     c
        inc     a
        jr      z, hrust_8098
        sub     #0x10
hrust_80A9:
        ld      l, a
        ld      c, a
        ld      h, #0xFF
        add     hl, de
        ldi
        dec     sp
        pop     af
        ld      (de), a
        inc     hl
        inc     de
        ld      a, (hl)
        jr      hrust_803A
hrust_80B8:
        ld      a, #0x80
hrust_80BA:
        add     hl, hl
        djnz    hrust_80BF
        pop     hl
        ld      b, c
hrust_80BF:
        adc     a, a
        jr      nz, hrust_80DB
        jr      c, hrust_80BA
        ld      a, #0xFC
        jr      hrust_80DE
hrust_80C8:
        dec     sp
        pop     bc
        ld      c, b
        ld      b, a
        ccf
        jr      hrust_8064
hrust_80CF:
        cp      #0x0F
        jr      c, hrust_80C8
        jr      nz, hrust_8063
        add     a, #0xF4
        ld      sp, ix
        jr      hrust_80EF
hrust_80DB:
        sbc     a, a
        ld      a, #0xEF
hrust_80DE:
        add     hl, hl
        djnz    hrust_80E3
        pop     hl
        ld      b, c
hrust_80E3:
        rla
        jr      c, hrust_80DE
        exx
        jr      nz, hrust_80A9
        bit     7, a
        jr      z, hrust_80CF
        sub     #0xEA
hrust_80EF:
        ex      de, hl
hrust_80F0:
        pop     de
        ld      (hl), e
        inc     hl
        ld      (hl), d
        inc     hl
        dec     a
        jr      nz, hrust_80F0
        ex      de, hl
        jr      nc, hrust_8096
        ret
