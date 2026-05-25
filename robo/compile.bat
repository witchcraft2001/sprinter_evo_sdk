@echo off

rem имя SCL файла

set output=robo.scl

rem сообщение, которое отображается при загрузке
rem 32 символа, стандартный шрифт

set title=" CODENAME ROBO IS LOADING"

rem список изображений, откуда брать палитры
rem в программе они вызываются по автоматически генерируемым
rem идентификаторам в файле resources.h
rem нумерация после точки должна быть возрастающей

set palette.0=tiles.bmp
set palette.1=final_boss.bmp
set palette.2=main4.bmp
set palette.20=intro1.bmp
set palette.21=intro2.bmp
set palette.22=intro3.bmp
set palette.23=intro4.bmp
set palette.24=intro5.bmp
set palette.25=intro6.bmp
set palette.26=intro7.bmp
set palette.27=intro_8.bmp
set palette.28=intro90.bmp
set palette.29=intro91.bmp
set palette.30=intro92.bmp
set palette.31=intro93.bmp
set palette.32=intro94.bmp
set palette.33=intro10.bmp
set palette.34=intro11_1.bmp
set palette.35=intro11_2.bmp
set palette.36=intro11_3.bmp
set palette.37=intro11_4.bmp
set palette.38=pause2.bmp
set palette.39=outro1.bmp
set palette.40=outro2.bmp
set palette.41=outro3.bmp
set palette.42=outro4.bmp
set palette.43=outro5.bmp
set palette.44=shop.bmp
set palette.45=title.bmp
set palette.46=game_over.bmp

rem список изображений, откуда брать графику

set image.0=tiles.bmp
set image.1=font.bmp
set image.2=pause2.bmp
set image.3=health.bmp
set image.4=shop.bmp
set image.5=final_boss.bmp
set image.6=main0.bmp
set image.7=main1.bmp
set image.8=main2.bmp
set image.9=main3.bmp
set image.10=main4.bmp
set image.11=intro1.bmp
set image.12=intro2.bmp
set image.13=intro3.bmp
set image.14=intro4.bmp
set image.15=intro5.bmp
set image.16=intro6.bmp
set image.17=intro7.bmp
set image.18=intro_8.bmp
set image.19=intro90.bmp
set image.20=intro91.bmp
set image.21=intro92.bmp
set image.22=intro93.bmp
set image.23=intro94.bmp
set image.24=intro10.bmp
set image.25=master_mind.bmp
set image.26=master_mind2.bmp
set image.27=intro11_1.bmp
set image.28=intro11_2.bmp
set image.29=intro11_3.bmp
set image.30=intro11_4.bmp
set image.31=outro1.bmp
set image.32=outro2.bmp
set image.33=outro3.bmp
set image.34=outro4.bmp
set image.35=outro5.bmp
set image.36=sprites.bmp
set image.37=title.bmp
set image.38=game_over.bmp
rem спрайты

set sprite.0=sprites.bmp

rem набор звуковых эффектов, если нужен
rem он может быть только один

set soundfx=robo.afb

rem музыка, нужное число треков

set music.0=robo2.pt3
set music.1=robo4.pt3
set music.2=robo4_.pt3
set music.3=long_path_tempo_cut.pt3
set music.4=long_path.pt3
set music.5=dreamofmermaid2012.pt3
rem сэмплы

set sample.0=bell.wav

rem Sprinter target: this file is treated as a manifest by
rem sprinter/tools/evoasm.py -- the original Evo SDK call/emullvd lines
rem are not used here. See Makefile.
