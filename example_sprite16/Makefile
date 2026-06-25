PROJECT := .

# Native Sprinter screen (full 320x256, per-pixel X) + the opt-in immediate-mode
# 16x16 accel blit draw_sprite16(). SPRITE16=1 assembles the primitive into the
# SDK; without it draw_sprite16 is absent (and existing games stay byte-identical).
NATIVE := 1
SPRITE16 := 1

all: exe

include ../sprintersdk/sprinter.mk
