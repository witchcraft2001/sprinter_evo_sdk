// Native Sprinter 256-colour palette test.
//
// Proves the full-precision 256-colour palette path of the Sprinter port over a
// real full-screen 320x256, 256-colour photo. The Sprinter palette register is
// 8 bits/channel (24-bit colour), not the 6-bit RGB222 of the EvoSDK 16-colour
// API. It exercises:
//   * pal_select()      -- apply all 256 entries of a 256-colour asset at full
//                          8-bit/channel depth (auto-detected from the palette);
//   * pal_load256()     -- load a full 256-entry palette computed in C memory;
//   * pal_bright()      -- coarse steady brightness (the level pal_select loads at).
//
// Two effects, both driven by recolouring the SAME pixels via the palette only
// (the photo's pixel data never changes):
//   1. Desaturation  -- smooth fade to grayscale and back (the Avalanche
//                       "Game-Over обесцвечивание" look).
//   2. Day/night     -- a tint cycle over the photo's real colours.
//
// alps_pal.h holds the photo's real 256-colour palette (pal_copy exposes only the
// low 16 entries, so the effect maths needs the full palette embedded). Regenerate
// with `python3 genpal.py` after changing alps.png.
//
// Exit: Space (or Esc = Caps+Space) returns to DSS. Sprinter-only.

#include <evo.h>
#include "resources.h"
#include "alps_pal.h"

// Computed 256 * (R8,G8,B8) palette pushed to hardware by pal_load256. Big arrays
// must be static (SDK rule -- SDCC has no heap and a tiny stack).
static u8 cbuf[768];

#ifdef __SPRINTER__
static u8 kb[40];                         // keyboard() fills 8 rows x 5 keys
#endif

// Quit to DSS on Space (covers Esc = Caps+Space too). No-op off Sprinter.
static void quit_if_asked(void)
{
#ifdef __SPRINTER__
	keyboard(kb);
	if (kb[KEY_SPACE] & KEY_DOWN) quit_to_dss();
#endif
}

// One presented frame + exit poll.
static void tick(void)
{
	swap_screen();
	quit_if_asked();
}

// Rec.601 luma of an 8-bit RGB triple (0.299/0.587/0.114, fixed-point /256).
static u8 luma(u8 r, u8 g, u8 b)
{
	return (u8)(((u16)r * 77 + (u16)g * 150 + (u16)b * 29) >> 8);
}

// Effect 1: blend the photo palette toward grayscale. mix 0 = full colour,
// 256 = full grayscale.
static void build_desat(u16 mix)
{
	const u8 *src = g_alps_pal;
	u8 *dst = cbuf;
	u16 i, inv;
	u8 r, g, b, y;
	inv = (u16)(256 - mix);
	for (i = 0; i < 256; ++i)
	{
		r = *src++; g = *src++; b = *src++;
		y = luma(r, g, b);
		*dst++ = (u8)(((u16)r * inv + (u16)y * mix) >> 8);
		*dst++ = (u8)(((u16)g * inv + (u16)y * mix) >> 8);
		*dst++ = (u8)(((u16)b * inv + (u16)y * mix) >> 8);
	}
}

// Effect 2: multiply the photo palette by a per-channel tint. tr/tg/tb in 0..256
// (256 = channel unchanged).
static void build_tint(u16 tr, u16 tg, u16 tb)
{
	const u8 *src = g_alps_pal;
	u8 *dst = cbuf;
	u16 i;
	for (i = 0; i < 256; ++i)
	{
		*dst++ = (u8)(((u16)*src++ * tr) >> 8);
		*dst++ = (u8)(((u16)*src++ * tg) >> 8);
		*dst++ = (u8)(((u16)*src++ * tb) >> 8);
	}
}

// Linear interpolate a..b by s (0..256), no division.
static u16 lerp(u16 a, u16 b, u16 s)
{
	return (u16)(((u32)a * (256 - s) + (u32)b * s) >> 8);
}

void main(void)
{
	static u16 t;
	static u16 s;

	pal_bright(BRIGHT_MID);                // coarse steady level = full brightness

	// Full 320x256 surface: the photo covers the whole native screen (no 320x200
	// centering, no border). Draw into both buffers so either swap shows it.
	clear_screen(0);
	draw_image(0, 0, IMG_ALPS);
	swap_screen();
	clear_screen(0);
	draw_image(0, 0, IMG_ALPS);
	swap_screen();

	pal_select(PAL_ALPS);                  // real photo, full 256 colours, 8-bit

	while (1)
	{
		// Hold the real photo.
		for (t = 0; t < 120; ++t) tick();

		// (1) Desaturate to grayscale (mix 0 -> 256), hold, then back to colour.
		for (t = 0; t <= 32; ++t) { build_desat((u16)(t << 3)); pal_load256(cbuf); tick(); }
		for (t = 0; t < 70; ++t) tick();
		for (t = 32; t != 0; --t) { build_desat((u16)(t << 3)); pal_load256(cbuf); tick(); }
		pal_select(PAL_ALPS);              // exact full colour again
		for (t = 0; t < 60; ++t) tick();

		// (2) Day/night tint cycle over the photo's real colours. Triangle phase
		//     s: 0 = bright day, 256 = dim cool night, and back.
		for (t = 0; t < 512; ++t)
		{
			s = (t < 256) ? t : (u16)(511 - t);             // 0..256..0
			build_tint(lerp(256, 90, s), lerp(248, 110, s), lerp(220, 205, s));
			pal_load256(cbuf);
			tick();
		}

		// Restore the exact photo palette and loop.
		pal_select(PAL_ALPS);
	}
}
