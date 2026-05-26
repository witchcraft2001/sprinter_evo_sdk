@echo off

rem Smoke test for the Sprinter PRELOAD/CACHE boot path (no assets).
rem Mirrors the empty_project manifest -- all resource sets empty.

set output=colortest.scl

set title=" COLOR TEST"

set palette.0=

set image.0=

set sprite.0=

set soundfx=

set music.0=

set sample.0=

call ..\evosdk\_compile.bat
@if %error% ==0 ..\evosdk\tools\unreal_evo\emullvd %output%
