; =========================================================================
;  loader.asm -- Sprinter DSS PRELOAD loader for the EvoSDK C image.
; =========================================================================
;  Linked standalone at LOADER_ORG (#4100, WIN1) and emitted verbatim into
;  the monoblock EXE by tools/dss_exe.py. DSS reads only this loader (LOADER
;  field in the EXE header) to #4100, jumps here with the EXE file left OPEN,
;  FM (file handle) at (IX-3), file position right after the loader bytes.
;
;  Memory discipline (HW_NOTES §9.2, §11.3; first-source: Estex-DSS +
;  evosdk_libs/sprinter). The game runs with CACHE on (WIN0=SRAM = hot SDK
;  code); this loader runs in WIN1 (DRAM) with CACHE off (WIN0=DSS BIOS) so
;  RST #10 reaches DSS. It never maps anything into WIN1 under itself --
;  all page staging goes through WIN2.
;
;  Sequence:
;    1. Save FM, original SLOT0, original video mode (DSS GetVMod).
;    2. Read the 16-byte body mini-header (K code chunks, M asset pages,
;       meta_size, hot_size, entry).
;    3. DSS SetVMod #81 (320x256x8) on both buffer pages -- done here while
;       WIN0=DSS, so the SRAM runtime never has to call DSS for video.
;    4. For each of K code chunks: GetMem a page, map it to WIN2, Dss.Read
;       16 KB into #8000. chunk0 -> SRAM(hot), 1->WIN1, 2->WIN2(data+tables),
;       3->WIN3(_DATA/_BSS).
;    5. Read EVP1 metadata into the WIN2 table region (#B100), and M asset
;       pages into fresh GetMem pages recorded in the page table (#B000).
;    6. Fill #B000 region: page table, saved SLOT0, saved video mode.
;    7. CACHE on (OUT #8F,0 / IN #FB); LDIR chunk0 page (mapped to WIN3) into
;       WIN0 SRAM at #0000. Map WIN1/WIN2/WIN3 to their final pages.
;    8. LD A,<WIN1 page>; JP entry (#2400). crt0 _entry does OUT (#A2),A.
;
;  No relocation: instruction fetch stays in WIN1 (this code) until JP entry,
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
GAME_ENTRY  =       0x2400          ; crt0 _entry (in SRAM after cache-on)

; ---- loader scratch, fixed in the loader's own WIN1 page (#4000-#7FFF) ----
;      (not in _DATA/_BSS, so the loader binary == pure code; FM lands right)
l_fm        =       0x7C00          ; file handle
l_slot0     =       0x7C01          ; original WIN0 page (cache-off baseline)
l_vmode     =       0x7C02          ; original DSS video mode
l_K         =       0x7C03          ; code chunk count
l_M         =       0x7C04          ; asset page count
l_meta      =       0x7C06          ; word: EVP1 meta byte count
l_hot       =       0x7C08          ; word: bytes of chunk0 to copy into SRAM
l_entry     =       0x7C0A          ; word: game entry
l_pages     =       0x7C10          ; 4 bytes: code chunk physical pages
l_assets    =       0x7C20          ; up to 64 bytes: asset physical pages
l_hdr       =       0x7C80          ; 16-byte mini-header read buffer
LOADER_SP   =       0x7FFD          ; loader stack top (own WIN1 page)

; ---- runtime tables, in the WIN2 data page (#8000-#BFFF), at #B000-#BFFF ----
;      DRAM, cache-independent, NOT remapped during draws. The SRAM runtime
;      and the DRAM exit trampoline both read here. Must match the SDK EQUs.
EVO_PAGE_TABLE = 0xB000             ; asset physical page numbers (index=logical)
EVO_PAGE_COUNT = 0xB040             ; byte: M
EVO_META       = 0xB100             ; EVP1 header+metadata copy
EVO_SAVED_SLOT0= 0xB400             ; byte: original WIN0 page
EVO_SAVED_VMODE= 0xB401             ; byte: original DSS video mode

; =========================================================================
_loader_entry::
        di
        ld      sp, #LOADER_SP

        ; --- 1. FM = (IX-3); save original SLOT0 + video mode ---
        ld      a, -3(ix)
        ld      (l_fm), a
        in      a, (SLOT0)
        ld      (l_slot0), a

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

        ; --- 3. set video mode #81 on both buffer pages (WIN0=DSS here) ---
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

        ; --- 4. load K code chunks (each: GetMem -> WIN2 -> read 16K) ---
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
        out     (SLOT2), a              ; WIN2 = chunk page
        call    read_16k_win2
        pop     bc
        inc     b
        jr      load_code_loop
load_code_done:

        ; --- 5. EVP1 metadata into the WIN2 table region (chunk2 page) ---
        ld      a, (l_pages+2)
        out     (SLOT2), a              ; WIN2 = chunk2 (data/table page)
        ld      hl, (l_meta)
        ld      a, h
        or      l
        jr      z, load_assets          ; meta_size 0 -> skip
        ld      de, (l_meta)
        ld      hl, #EVO_META
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix

        ; --- 5b. M asset pages (GetMem -> WIN2 -> read 16K), record page no ---
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
        out     (SLOT2), a
        call    read_16k_win2
        pop     bc
        inc     b
        jr      asset_loop
asset_done:

        ; --- 6. fill the table region in the chunk2 page (map it back) ---
        ld      a, (l_pages+2)
        out     (SLOT2), a
        ld      a, (l_M)
        ld      (EVO_PAGE_COUNT), a
        ld      a, (l_slot0)
        ld      (EVO_SAVED_SLOT0), a
        ld      a, (l_vmode)
        ld      (EVO_SAVED_VMODE), a
        ; copy l_assets[0..M-1] -> EVO_PAGE_TABLE
        ld      a, (l_M)
        or      a
        jr      z, tables_done
        ld      c, a
        ld      b, #0
        ld      hl, #l_assets
        ld      de, #EVO_PAGE_TABLE
        ldir
tables_done:

        ; --- 7. CACHE on, LDIR chunk0 (mapped via WIN3) into WIN0 SRAM ---
        ld      a, (l_pages+0)
        out     (SLOT3), a              ; WIN3 = chunk0 (hot) page
        xor     a
        out     (CACHE_PAGE), a         ; ROM_RG = 0
        in      a, (CACHE_ON)           ; WIN0 = SRAM
        ld      hl, #0xC000             ; WIN3 view of chunk0
        ld      de, #0x0000             ; SRAM
        ld      bc, (l_hot)
        ldir

        ; --- map final windows: WIN1=chunk1, WIN2=chunk2, WIN3=chunk3 ---
        ld      a, (l_pages+2)
        out     (SLOT2), a
        ld      a, (l_K)
        cp      #4
        jr      c, no_win3
        ld      a, (l_pages+3)
        out     (SLOT3), a
no_win3:
        ; --- 8. enter game: A = WIN1 page; crt0 _entry does OUT (#A2),A ---
        ld      a, (l_pages+1)
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

; read_16k_win2: Dss.Read 0x4000 bytes from FM into #8000 (WIN2).
read_16k_win2:
        ld      hl, #0x8000
        ld      de, #0x4000
        ld      a, (l_fm)
        ld      c, #DSS_READ
        push    ix
        rst     #0x10
        pop     ix
        ret
