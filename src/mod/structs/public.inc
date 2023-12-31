;==============================================================================
; MOD player
;------------------------------------------------------------------------------
; Public structures
;==============================================================================

;------------------------------------------------------------------------------
; Parameters for MOD player output devices. This is just a generic table, refer
; to the output device for details on what to provide as an input for each of
; them.
;------------------------------------------------------------------------------

struc		mod_dev_params

.buffer_size	resd 1			; Output buffer size in microseconds
.port		resw 2			; IO port addresses
.irq		resb 2			; IRQ addresses
.dma		resb 2			; DMA channels
.stereo_mode	resb 1			; Stereo mixing mode
.initial_pan	resb 1			; Initial panning for real stereo mode
.interpolation	resb 1			; Sample interpolation
		alignb 4
.strucsize:

endstruc

;------------------------------------------------------------------------------
; MOD information structure.
;------------------------------------------------------------------------------

struc		mod_info

.title		resb 21			; Song title (ASCIIZ)
.num_channels	resb 1			; Number of channels
.num_samples	resb 1			; Number of samples
.length		resb 1			; Number of entries in pattern sequence
.num_patterns	resb 1			; Number of patterns in song
.restart_pos	resb 1			; Restart position
		alignb 4
.flags		resd 1			; MOD flags (MOD_FLG_*)
.sequence_addr	resd 1			; Linear address of sequence data
.pattern_addr	resd 1			; Linear address of pattern data
.samples:				; mod_sample_info starts here
.strucsize:

endstruc

;------------------------------------------------------------------------------
; MOD position and speed information structure.
;------------------------------------------------------------------------------

struc		mod_position_info

.position	resb 1			; Position within pattern sequence
.pattern	resb 1			; Pattern number
.row		resb 1			; Row within pattern
.tick		resb 1			; Tick within row
.speed		resb 1			; Number of ticks per row
.bpm		resb 1			; Beats per minute
		alignb 4
.strucsize:

endstruc

;------------------------------------------------------------------------------
; MOD sample information structure.
;------------------------------------------------------------------------------

struc		mod_sample_info

.name		resb 23			; ASCIIZ name of the sample
		alignb 4
.addr		resd 1			; Linear address of sample data
.length		resd 1			; Sample length in bytes
.rpt_start	resd 1			; Sample loop repeat start position
.rpt_len	resd 1			; Sample loop repeat length
		alignb 4
.strucsize:

endstruc

;------------------------------------------------------------------------------
; MOD channel information structure.
;------------------------------------------------------------------------------

struc		mod_channel_info

.period		resd 1			; Current playback period * 16
.sample_pos_int	resd 1			; Current sample position
.sample_pos_fr	resw 1			; Current sample position fraction
.sample		resb 1			; Sample number (0 - 32)
.volume		resb 1			; Channel volume (0 - 64)
.pan		resb 1			; Channel pan (0 - 255)
		alignb 4
.strucsize:

endstruc

;------------------------------------------------------------------------------
; MOD output device information structure.
;------------------------------------------------------------------------------

struc		mod_output_info

.sample_rate	resd 1			; Actual output sample rate
.buffer_addr	resd 1			; Linear address of output buffer
.buffer_size	resd 1			; Size of buffer in bytes
.buffer_pos	resd 1			; Current buffer playback position
.buffer_format	resb 1			; Buffer audio format
		alignb 4
.strucsize:

endstruc