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
;       meta_size, hot_size, entry).
;    3. DSS SetVMod #81 (320x256x8) on both buffer pages -- done here while
;       WIN0=DSS, so the SRAM runtime never has to call DSS for video.
;    4. For each of K code chunks: GetMem a page, map it to WIN1, Dss.Read
;       16 KB into #4000. chunk0 -> SRAM(hot), 1->WIN1, 2->WIN2, 3->WIN3.
;    5. Read EVP1 metadata + M asset pages; record asset pages in the table.
;    6. Write the SDK tables (page table #1A00, saved vmode #1A40) into chunk0
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

VIDEO_MODE  =       0x81            ; 320x256x8bpp

; ---- loader scratch, fixed high in the loader's own WIN2 page (#8000-#BFFF) ----
;      (above the loader code; not in _DATA/_BSS, so the binary == pure code)
l_fm        =       0xBC00          ; file handle
l_vmode     =       0xBC02          ; original DSS video mode
l_K         =       0xBC03          ; code chunk count
l_M         =       0xBC04          ; asset page count
l_meta      =       0xBC06          ; word: EVP1 meta byte count
l_hot       =       0xBC08          ; word: bytes of chunk0 to copy into SRAM
l_entry     =       0xBC0A          ; word: game entry
l_pages     =       0xBC10          ; 4 bytes: code chunk physical pages
l_assets    =       0xBC20          ; up to 64 bytes: asset physical pages
l_hdr       =       0xBC80          ; 16-byte mini-header read buffer
LOADER_SP   =       0xBFFF          ; loader stack top (own WIN2 page)

; ---- SDK runtime tables live in the SDK SRAM region (mirror of EvoSDK
;      #E000-#FFFF). The loader writes them into chunk0 (which it then LDIRs into
;      SRAM) through the WIN1 staging view: while chunk0 is mapped to WIN1, its
;      offset X is reachable at #4000+X. MUST match lib_startup.asm/lib_tiles.asm.
EVO_PAGE_TABLE   = 0x1A00           ; SRAM: asset phys page table (index=logical)
EVO_SAVED_VMODE  = 0x1A40           ; SRAM: original DSS video mode (for exit)
EVO_META         = 0x1B00           ; SRAM: EVP1 header+metadata copy
STAGE            = 0x4000           ; WIN1 view base of a page during staging
STAGE_PAGE_TABLE = STAGE + EVO_PAGE_TABLE
STAGE_SAVED_VMODE = STAGE + EVO_SAVED_VMODE
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
        ld      hl, (l_hdr+4)           ; meta_size
        ld      (l_meta), hl
        ld      hl, (l_hdr+6)           ; hot_size
        ld      (l_hot), hl
        ld      hl, (l_hdr+8)           ; entry
        ld      (l_entry), hl

        ; --- 3. set video mode #81 on both screen pages, same order as
        ;        flappybird ChangeVideoMode: B=1, then B=0. WIN0=DSS here;
        ;        this clobbers WIN1, which is fine -- the loader is in WIN2. ---
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

        ; --- 4. load K code chunks (each: GetMem -> WIN1 -> read 16K) ---
        ld      b, #0                   ; chunk index
load_code_loop:
        ld      a, (l_K)
        cp      b
        jr      z, load_code_done
        push    bc
        call    getmem_page             ; A = phys page
        pop     bc
        push    bc
        ld      c, b
        ld      b, #0
        ld      hl, #l_pages
        add     hl, bc                  ; &l_pages[i]
        ld      (hl), a
        out     (SLOT1), a              ; WIN1 = chunk page
        call    read_16k_win1
        pop     bc
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

        ; --- 5b. M asset pages (GetMem -> WIN1 -> read 16K), record page no ---
load_assets:
        ld      b, #0
asset_loop:
        ld      a, (l_M)
        cp      b
        jr      z, asset_done
        push    bc
        call    getmem_page
        pop     bc
        push    bc
        ld      c, b
        ld      b, #0
        ld      hl, #l_assets
        add     hl, bc
        ld      (hl), a                 ; l_assets[j] = phys page
        out     (SLOT1), a
        call    read_16k_win1
        pop     bc
        inc     b
        jr      asset_loop
asset_done:

        ; --- 6. fill the SDK tables in chunk0 (staged in WIN1) ---
        ld      a, (l_pages+0)
        out     (SLOT1), a              ; WIN1 = chunk0
        ld      a, (l_vmode)
        ld      (STAGE_SAVED_VMODE), a  ; saved video mode (for exit)
        ld      a, (l_M)
        or      a
        jr      z, tables_done
        ld      c, a
        ld      b, #0
        ld      hl, #l_assets
        ld      de, #STAGE_PAGE_TABLE   ; copy asset phys pages -> page table
        ldir
tables_done:

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
; getmem_page: DSS GetMem 1 page -> A = physical page. On error, halts
;   (no graceful path yet; the EXE is sized so allocation should succeed).
getmem_page:
        push    ix
        ld      b, #1
        ld      c, #DSS_GETMEM
        rst     #0x10
        pop     ix
        ret     nc
        di
        halt                            ; out of memory (TODO: clean Dss.Exit)

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
