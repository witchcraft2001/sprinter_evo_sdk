@echo off

set output=sprite16.scl

rem 32 chars max -- loading banner
set title=" DRAW_SPRITE16 CASCADE TEST"

rem 16-colour ball palette (index 0 = black background) + 16x16 sprite sheet.
set palette.0=balls.bmp
set sprite.0=balls.bmp

set soundfx=
set music.0=
