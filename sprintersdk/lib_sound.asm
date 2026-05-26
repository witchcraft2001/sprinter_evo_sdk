; =========================================================================
;  lib_sound.asm -- music / sfx / sample playback (EvoSDK responsibility zone)
; =========================================================================
;  Public API: music_play/stop, sfx_play/stop, sample_play.
;  Mirrors evosdk/lib_sound.asm. Stubs until the players are ported (Этап 5:
;  PT3 via CTC/IM2, AFX, CBL sample playback -- see HW_NOTES §6/§7).
; =========================================================================

        .module lib_sound

        .globl  _sfx_play
        .globl  _sfx_stop
        .globl  _music_play
        .globl  _music_stop
        .globl  _sample_play

        .area   _CODE

_sfx_play::
_sfx_stop::
_music_play::
_music_stop::
_sample_play::
        ret
