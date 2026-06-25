@echo off

set output=native.scl

rem 32 chars max -- loading banner
set title=" 256-COLOUR PALETTE TEST"

rem Full-screen 320x256 256-colour photo + its 256-entry master palette.
rem palette.0 and image.0 share the same asset so PAL_ALPS / IMG_ALPS line up.
set palette.0=alps.png
set image.0=alps.png

set soundfx=
set music.0=
