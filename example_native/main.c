// Native Sprinter screen demo (build with NATIVE=1, the default for this project).
//
// Shows the two native-mode capabilities over the EvoSDK-compatible defaults:
//   * full 320x256 surface (no 320x200 centering) -- sprites reach y up to 240;
//   * per-pixel sprite X over the full width 0..319 (no 2-pixel granularity) --
//     sprites reach x up to 303 and can sit at odd X positions.
// The same set_sprite() in compatibility mode would treat x as 2-pixel units
// (0..152) and clip anything past the centered 320x200 area.

#include <evo.h>
#include "resources.h"

#define SCR_W   320
#define SCR_H   256
#define SPR     16              // sprite is 16x16
#define X_MAX   (SCR_W - SPR)   // 304: rightmost on-screen X
#define Y_MAX   (SCR_H - SPR)   // 240: bottommost on-screen Y

void main(void)
{
	static u8 i, frame, cell;
	static i16 sweep, dir;
	static u8 palette[16];

	pal_bright(BRIGHT_MIN);          // black while we set up

	// Background: clear the WHOLE 320x256 surface, then draw the 320x200 image at
	// the top. In native mode the bottom 56 rows are live surface (not a border),
	// so they take the clear colour -- visible proof the full screen is in use.
	clear_screen(0);
	draw_image(0, 0, IMG_BACK);
	swap_screen();
	clear_screen(0);
	draw_image(0, 0, IMG_BACK);
	swap_screen();

	sprites_start();

	// Palette: background colours 0..5, sprite colours 6..15 (one 256-cell palette,
	// partitioned -- same idea as the EvoSDK examples).
	pal_copy(PAL_BACK, palette);
	for (i = 0; i < 6; ++i) pal_col(i, palette[i]);
	pal_copy(PAL_BALLS, palette);
	for (i = 6; i < 16; ++i) pal_col(i, palette[i]);

	pal_bright(BRIGHT_MID);          // reveal

	sweep = 0;
	dir = 1;
	frame = 0;

	while (1)
	{
		cell = SPR_BALLS + ((frame >> 3) & 3);   // animate the ball cell

		// Sprite 0: smooth PER-PIXEL sweep across the FULL width (0..X_MAX).
		// 1 px/frame -- in compatibility mode the step would be 2 px.
		set_sprite(0, (u16)sweep, 120, cell);

		// Sprites 1..4: the four extreme corners of the 320x256 surface. The
		// right column (x=303) and bottom row (y=240) are reachable ONLY in
		// native mode -- compatibility mode would clip them away.
		set_sprite(1, 0,     0,     SPR_BALLS);
		set_sprite(2, X_MAX, 0,     SPR_BALLS);
		set_sprite(3, 0,     Y_MAX, SPR_BALLS);
		set_sprite(4, X_MAX, Y_MAX, SPR_BALLS);

		// Sprites 5..12: a diagonal at ODD, per-pixel X positions spanning the
		// whole width -- impossible to express at 2-pixel granularity.
		for (i = 0; i < 8; ++i)
			set_sprite(5 + i, (u16)(7 + i * 37), 24 + i * 26, SPR_BALLS + (i & 3));

		swap_screen();

		++frame;
		sweep += dir;
		if (sweep >= X_MAX) { sweep = X_MAX; dir = -1; }
		else if (sweep <= 0) { sweep = 0; dir = 1; }
	}
}
