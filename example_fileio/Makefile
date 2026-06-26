PROJECT := .

# Blocking DSS file I/O into paged memory (FILEIO=1). NATIVE for the 320x256
# screen. NB: FILEIO requires the loader to hand off a trampoline page (work in
# progress) -- until then file_* return -1 (the SDK guards against a null page).
NATIVE := 1
FILEIO := 1

all: exe

include ../sprintersdk/sprinter.mk
