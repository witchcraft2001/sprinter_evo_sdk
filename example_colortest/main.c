// Smoke test for the Sprinter EvoSDK port boot path (M1).
//
// Uses only wired primitives -- palette + clear_screen + swap_screen -- so it
// needs no tile/sprite pipeline (M2). It exercises the whole chain end to end:
//   loader -> CACHE on / SDK in SRAM -> crt0 -> runtime_init (video set by
//   loader, palette + clear) -> main -> exit trampoline (CACHE off -> DSS.Exit).
//
// Expected on screen: a full-screen RED, then GREEN, then BLUE (each held a few
// seconds), after which the program returns cleanly to DSS.

#include <evo.h>
#include "resources.h"

static u16 j;

static void hold(u8 color)
{
	// Fill both double-buffer pages with the colour, then hold it on screen.
	clear_screen(color);
	swap_screen();
	clear_screen(color);
	swap_screen();
	for (j = 0; j < 8000; ++j) swap_screen();
}

void main(void)
{
	// Bright primaries in R2G2B2 (6-bit: %RRGGBB).
	pal_col(1, 0x30);   // red
	pal_col(2, 0x0C);   // green
	pal_col(3, 0x03);   // blue

	hold(1);
	hold(2);
	hold(3);
	// return -> crt0 -> runtime_shutdown -> DSS.Exit
}
