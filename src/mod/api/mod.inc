;==============================================================================
; MOD player
;------------------------------------------------------------------------------
; Public API
;==============================================================================

%include "mod/consts/public.inc"
%include "mod/structs/public.inc"

extern mod_sb_detect
extern mod_setup
extern mod_shutdown
extern mod_load
extern mod_unload
extern mod_set_amplify
extern mod_set_interpolation
extern mod_set_stereo_mode
extern mod_play
extern mod_get_position
extern mod_set_position
extern mod_stop
extern mod_render
extern mod_get_info
extern mod_get_channel_info
extern mod_get_output_info
extern mod_get_position_info
extern mod_perf_ticks
