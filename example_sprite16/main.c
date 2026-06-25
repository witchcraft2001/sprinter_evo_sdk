// Immediate-mode cascade test for draw_sprite16() (build flag SPRITE16=1).
//
// Proves the things the 64-entry set_sprite list cannot do:
//   * MORE THAN 64 simultaneous 16x16 cells (here 100) -- draw_sprite16 takes no
//     queue slot, so there is no 64-sprite limit;
//   * per-pixel smooth vertical motion (the list path is fine too, but a cascade
//     of >64 cells could not run on it at all);
//   * hardware masked blit (index 255 transparent) straight into the hidden buffer.
//
// The defining contract of immediate mode: the background is NOT auto-restored
// (no saved rect). The caller redraws it every frame -- here clear_screen() -- and
// that is what erases the previous frame's cells. sprites_start() is deliberately
// NEVER called, so swap_screen() is a plain flip and the immediate blits compose
// directly. This mirrors Avalanche's hybrid field render.
//
// Exit: Space (or Esc = Caps+Space) returns to DSS. Sprinter-only.

#include <evo.h>
#include "resources.h"

#define N      100             // > 64: impossible on the set_sprite list
#define X_MAX  304             // rightmost on-screen X for a 16-wide cell
#define Y_MAX  240             // bottommost on-screen Y for a 16-tall cell

// Per-cell state. Big arrays must be static (SDK rule -- no heap, tiny stack).
static u16 px[N];
static u8  py[N];
static u8  spd[N];
static u8  cel[N];
static u8  kb[40];             // keyboard() fills 8 rows x 5 keys

void main(void)
{
	static u16 i;

	// Scatter the cells across the screen with varied speed and cell.
	for (i = 0; i < N; ++i)
	{
		px[i]  = rand16() % (X_MAX + 1);          // 0..304, per-pixel X
		py[i]  = (u8)(rand16() % (Y_MAX + 1));    // 0..240
		spd[i] = (u8)(1 + (rand16() & 3));        // 1..4 px/frame
		cel[i] = (u8)(SPR_BALLS + (rand16() & 3));// one of the 4 ball cells
	}

	pal_bright(BRIGHT_MID);
	pal_select(PAL_BALLS);                        // 16-colour palette, index 0 = black

	while (1)
	{
		// Redraw the background (immediate blits leave no saved rect to restore).
		clear_screen(0);

		// Blit all N cells straight into the hidden buffer, masked. No slot, no
		// 64 limit. flags 0 = transparent (skip index 255).
		for (i = 0; i < N; ++i)
			draw_sprite16(px[i], py[i], cel[i], 0);

		swap_screen();

		// Advance the cascade: per-pixel fall, wrap back to the top.
		for (i = 0; i < N; ++i)
		{
			py[i] += spd[i];
			if (py[i] > Y_MAX) py[i] -= (Y_MAX + 1);
		}

		keyboard(kb);
		if (kb[KEY_SPACE] & KEY_DOWN) quit_to_dss();
	}
}
