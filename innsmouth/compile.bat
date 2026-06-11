@echo off

rem имя SCL файла

set output=innsmouth.scl

rem сообщение, которое отображается при загрузке
rem 32 символа, стандартный шрифт

set title="Entering into Innsmouth"

rem список изображений, откуда брать палитры
rem в программе они вызываются по автоматически генерируемым
rem идентификаторам в файле resources.h
rem нумерация после точки должна быть возрастающей

set palette.0=tiles.bmp
set palette.1=char.bmp
set palette.2=font.bmp
set palette.3=deep_one.bmp
set palette.4=gameover.bmp
set palette.5=title.bmp
set palette.6=win.bmp
set palette.8=scratch1.bmp
set palette.9=scratch2.bmp
rem список изображений, откуда брать графику

set image.0=tiles.bmp
set image.1=char.bmp
set image.2=font.bmp
set image.3=objects.bmp
set image.4=inventory.bmp
set image.5=sec_lay.bmp
set image.6=items.bmp
set image.7=deep_one.bmp
set image.8=scratch1.bmp
set image.9=scratch2.bmp
set image.10=roof.bmp
set image.11=basement.bmp
set image.12=gameover.bmp
set image.13=title.bmp
set image.14=win.bmp

rem Sprinter-only полноцветные версии картинок (оверрайды базовых изображений).
set sprinter_palette.0=sprinter\inventory.png
set sprinter_image.4=sprinter\inventory.png
set sprinter_palette.3=sprinter\deep_one.png
set sprinter_image.7=sprinter\deep_one.png
set sprinter_palette.8=sprinter\scratch1.png
set sprinter_image.8=sprinter\scratch1.png
set sprinter_palette.9=sprinter\scratch2.png
set sprinter_image.9=sprinter\scratch2.png
set sprinter_palette.5=sprinter\title.png
set sprinter_image.13=sprinter\title.png
set sprinter_palette.6=sprinter\win.png
set sprinter_image.14=sprinter\win.png
set sprinter_palette.4=sprinter\gameover.png
set sprinter_image.12=sprinter\gameover.png

rem Sprinter: полноцветные экраны, поверх которых рисуется старый UI/текст,
rem держат базовые 16 цветов в 0..15, а картинку -- в 16..255.
set palette_base.0=16
set palette_base.3=16
set palette_base.4=16
set palette_base.5=16
set palette_base.7=16
set palette_base.8=16
set palette_base.9=16
set palette_base.13=16
set palette_base.6=16
set palette_base.14=16
set palette_base.12=16
rem спрайты

set sprite.0=char.bmp

rem набор звуковых эффектов, если нужен
rem он может быть только один

set soundfx=

rem музыка, нужное число треков

set music.0=diamond.pt3
set music.1=diamond2.pt3

rem сэмплы

set sample.0=deepone.wav
set sample.1=slash.wav
set sample.2=inventory.wav
set sample.3=bell.wav
set sample.4=switch.wav

rem Sprinter target: this file is treated as a manifest by
rem sprinter/tools/evoasm.py -- the call/emullvd lines from the original
rem Evo SDK build are not used here. See Makefile.
