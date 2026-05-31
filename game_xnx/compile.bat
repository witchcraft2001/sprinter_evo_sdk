@echo off

rem имя SCL файла

set output=xnx.scl

rem сообщение, которое отображается при загрузке
rem 32 символа, стандартный шрифт

set title=" XNX IS LOADING"

rem список изображений, откуда брать палитры
rem в программе они вызываются по автоматически генерируемым
rem идентификаторам в файле resources.h
rem нумерация после точки должна быть возрастающей

set palette.0=gfx\title.bmp
set palette.1=gfx\textback1.bmp
set palette.2=gfx\textback2.bmp
set palette.3=gfx\textback3.bmp
set palette.10=gfx\pic1.bmp
set palette.11=gfx\pic2.bmp
set palette.12=gfx\pic3.bmp
set palette.13=gfx\pic4.bmp
set palette.14=gfx\pic5.bmp
set palette.15=gfx\pic6.bmp
set palette.16=gfx\pic7.bmp
set palette.17=gfx\pic8.bmp
set palette.18=gfx\pic9.bmp
set palette.19=gfx\pic10.bmp

rem список изображений, откуда брать графику

set image.0=gfx\title.bmp
set image.1=gfx\font816.bmp
set image.2=gfx\font2432.bmp
set color_key.2=1
set image.3=gfx\bgmask.bmp
set image.4=gfx\textback1.bmp
set image.10=gfx\pic1.bmp
set image.11=gfx\pic2.bmp
set image.12=gfx\pic3.bmp
set image.13=gfx\pic4.bmp
set image.14=gfx\pic5.bmp
set image.15=gfx\pic6.bmp
set image.16=gfx\pic7.bmp
set image.17=gfx\pic8.bmp
set image.18=gfx\pic9.bmp
set image.19=gfx\pic10.bmp

rem Sprinter-only полноцветные версии картинок (оверрайды базовых pic*)
set sprinter_palette.10=gfx\sp_pic1.bmp
set sprinter_image.10=gfx\sp_pic1.bmp
set sprinter_palette.11=gfx\sp_pic2.bmp
set sprinter_image.11=gfx\sp_pic2.bmp
set sprinter_palette.16=gfx\sp_pic7.bmp
set sprinter_image.16=gfx\sp_pic7.bmp
set sprinter_palette.17=gfx\sp_pic8.bmp
set sprinter_image.17=gfx\sp_pic8.bmp
set sprinter_palette.18=gfx\sp_pic9.bmp
set sprinter_image.18=gfx\sp_pic9.bmp
set sprinter_palette.19=gfx\sp_pic10.bmp
set sprinter_image.19=gfx\sp_pic10.bmp
set sprinter_palette.12=gfx\sp_pic3.bmp
set sprinter_image.12=gfx\sp_pic3.bmp
set sprinter_palette.13=gfx\sp_pic4.bmp
set sprinter_image.13=gfx\sp_pic4.bmp
set sprinter_palette.14=gfx\sp_pic5.bmp
set sprinter_image.14=gfx\sp_pic5.bmp
set sprinter_palette.15=gfx\sp_pic6.bmp
set sprinter_image.15=gfx\sp_pic6.bmp

rem Sprinter: полноцветные фоны делят палитру с UI — база (16 цв.) в 0..15, фото в 16..255
set palette_base.10=16
set palette_base.11=16
set palette_base.16=16
set palette_base.17=16
set palette_base.18=16
set palette_base.19=16
set palette_base.12=16
set palette_base.13=16
set palette_base.14=16
set palette_base.15=16

rem спрайты

set sprites.0=gfx\player.bmp
set sprites.1=gfx\titlemask.bmp
set sprites.2=gfx\spikeball.bmp

rem набор звуковых эффектов, если нужен
rem он может быть только один

set soundfx=sfx\sounds.afb

rem музыка, нужное число треков

set music.0=mus\intro.pt3
set music.1=mus\level.pt3
set music.2=mus\gameover.pt3
set music.3=mus\welldone.pt3
set music.10=mus\loop1.pt3

rem сэмплы

set sample.0=sfx\start.wav
set sample.1=sfx\meow.wav

call ..\evosdk\_compile.bat
@if %error% ==0 ..\evosdk\tools\unreal_evo\emullvd %output%