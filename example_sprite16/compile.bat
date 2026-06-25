@echo off

set output=sprite16.scl

rem 32 chars max -- loading banner
set title=" DRAW_SPRITE16 CASCADE TEST"

rem 16-colour ball palette (index 0 = black background) + 16x16 sprite sheet.
set palette.0=balls.bmp
set sprite.0=balls.bmp

rem Digitized SFX (22 kHz mono 8-bit) played non-blocking via sample_play_async
rem while the cascade runs -- the hardware test for SAMPLE_ASYNC. bell (~2.8s)
rem streams across many cascade frames; slash is a short on-demand hit.
set sample.0=bell.wav
set sample.1=slash.wav

set soundfx=
set music.0=
