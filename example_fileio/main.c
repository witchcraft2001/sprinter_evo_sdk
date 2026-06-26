// DSS file I/O test (FILEIO=1).
//
// Round-trips a buffer through a file in PAGED memory:
//   1. mem_alloc a 1-page block, resolve its physical page (mem_pages);
//   2. fill that page with a known pattern via page_poke/page_write;
//   3. file_create + file_write the page to "TEST.BIN";
//   4. file_read it back into a second offset of the page;
//   5. compare with page_peek; show PASS/FAIL as a screen colour.
//
// BLOCKING: each file_* call freezes interrupts/music/frame for its duration
// (CACHE off -> WIN0 = DSS BIOS). See evo.h / HW_NOTES.
//
// NB: until the loader hands off a trampoline page, file_*/mem_* return -1/0xFF
// (the SDK guards against a null trampoline page) -> this shows FAIL safely.
//
// Exit: Space / Esc (Caps+Space).

#include <evo.h>
#include "resources.h"

#define LEN 1024       // 2 full DSS sectors -- write/read/verify round-trip

static u8 kb[40];
static u8 buf[LEN];        // generated pattern
static u8 rb[LEN];         // read-back

// Solid-colour full screen as a pass/fail indicator.
static void show(u8 color)
{
	clear_screen(color);
	swap_screen();
	clear_screen(color);
	swap_screen();
}

static void hold(u16 f) { while (f--) swap_screen(); }

// Blink the screen green `cnt` times (count the flashes = the value), forever.
static void blink(u16 cnt)
{
	u16 i;
	for (;;)
	{
		for (i = 0; i < cnt; ++i) { show(2); hold(12); show(0); hold(12); }
		show(0);
		hold(100);                                     // long gap, then repeat
	}
}

void main(void)
{
	static u16 i;
	static u8  blk, page, pages, ok;
	static i16 h, n;

	pal_bright(BRIGHT_MID);
	pal_clear();
	pal_col(0, 0x00);          // 0 black
	pal_col(1, 0x30);          // 1 red     = create failed
	pal_col(2, 0x0C);          // 2 green   = PASS
	pal_col(3, 0x03);          // 3 blue    = mem_alloc failed (no handoff / inert)
	pal_col(4, 0x3C);          // 4 yellow  = mem_pages failed
	pal_col(5, 0x33);          // 5 magenta = write count wrong
	pal_col(6, 0x0F);          // 6 cyan    = open failed
	pal_col(7, 0x3F);          // 7 white   = read returned 0 (empty file)
	pal_col(8, 0x38);          // 8 orange  = partial READ (border = count/16)
	// (mismatch -> red too, but only reachable after all 4 ops succeed)

	ok = 0;

	// WRITE/READ/VERIFY round-trip: generate LEN bytes, write to TEST.BIN, close,
	// reopen, read back into a different page offset, compare.
	blk = mem_alloc(1);
	if (blk == 0xFF) { show(3); goto idle; }       // blue   = no trampoline page
	pages = mem_pages(blk, &page);
	if (pages == 0) { show(4); goto idle; }        // yellow = mem_pages failed

	for (i = 0; i < LEN; ++i) buf[i] = (u8)(i * 7 + 3);   // pattern
	page_write(page, 0, buf, LEN);                 // pattern -> page:0

	// --- write ---
	h = file_create("TEST.BIN");
	if (h < 0) { show(1); goto idle; }             // red = create failed
	n = file_write((u8)h, page, 0, LEN);
	file_close((u8)h);
	if (n != LEN)
	{
		if (n < 0)       { show(1); goto idle; }       // red     = write error (CF)
		else if (n == 0) { show(5); goto idle; }       // magenta = wrote 0 bytes
		else { show(8); hold(80); blink((u16)n); }     // orange + flashes = partial
	}

	// --- read back into page:0x2000 ---
	h = file_open("TEST.BIN", 1);                  // 1 = read
	if (h < 0) { show(6); goto idle; }             // cyan = open failed
	n = file_read((u8)h, page, 0x2000, LEN);
	file_close((u8)h);
	if (n != LEN)
	{
		if (n < 0)       { show(1); goto idle; }       // red    = read error
		else if (n == 0) { show(7); goto idle; }       // white  = read 0 (file empty)
		else { show(8); hold(80); blink((u16)n); }     // orange + flashes = partial
	}

	// --- verify: read page:0x2000 into rb, compare with the original pattern ---
	page_read(page, 0x2000, rb, LEN);
	ok = 1;
	for (i = 0; i < LEN; ++i)
		if (rb[i] != buf[i]) { ok = 0; break; }

	show(ok ? 2 : 1);                              // green = full PASS, red = mismatch

idle:
	while (1)
	{
		swap_screen();
		keyboard(kb);
		if (kb[KEY_SPACE] & KEY_DOWN) quit_to_dss();
	}
}
