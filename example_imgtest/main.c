// Isolation test for the paged tile renderer + palette (M2a). Same core as
// slideshow's show_picture, but NO fade and NO loop -- so it isolates
// draw_image + pal_select + double-buffer from the fade/joystick path.
//
// Expected: image 0 shown in pic1's real colours (via pal_select), stable.
//   * correct image+colours -> draw_tile + pal_select + buffer all work; the
//                              slideshow black is the fade/loop path.
//   * image, wrong/garbage colours -> pal_select loads the wrong data.
//   * black / offset image -> draw or buffer addressing.

#include <evo.h>
#include "resources.h"

void main(void)
{
	draw_image(0, 0, 0);       // image 0 -> hidden buffer
	pal_select(0);             // load image 0's palette (written to both pages)
	swap_screen();             // show the hidden buffer

	for (;;) vsync();          // hold (side effect -> not optimized away)
}
