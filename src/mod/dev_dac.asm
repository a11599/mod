;==============================================================================
; MOD player - DAC output device
;------------------------------------------------------------------------------
; Supports via software wavetable rendering:
; - PC speaker: 5.3 - 6-bits, up to 29000 Hz sample rate
;   (resolution inversely proportional to sample rate)
; - Parallel port DACs (aka. Covox): 8-bits, up to 100000 Hz sample rate:
;   - Mono LPT DAC on any parallel port
;   - Dual LPT DACs on any parallel ports in mono or stereo
;   - Stereo LPT DAC ("Stereo-on-1") on any parallel port in mono or stereo
;------------------------------------------------------------------------------
; All output devices utilize the timer interrupt (IRQ 0) for playback, which
; makes it unavailable for other purposes.
;------------------------------------------------------------------------------
; Performance same as software wavetable rendering, plus playback overhead due
; to timer interrupts (86Box 386DX clocks at 44192 Hz):
;
; DAC                        Cross mixing overhead MHz    Playback overhead MHz
; ---                        -------------------------    ---------------------
; Speaker/Mono LPT DAC                               -                      6.0
; Dual LPT DACs in stereo                         2.12                      6.0
; Stereo LPT DAC in stereo                        2.12                      7.2
;
; Cross mixing overhead (2.12 MHz) applies to stereo output with cross stereo
; mode only.
;==============================================================================

	cpu 386

section .text

%include "pmi/api/pmi.inc"
%include "rtl/api/string.inc"
%include "rtl/api/log.inc"
%include "rtl/api/irq.inc"
%include "rtl/api/timer.inc"

%include "mod/config.inc"
%include "mod/api/wtbl_sw.inc"
%include "mod/api/routine.inc"
%include "mod/structs/public.inc"
%include "mod/consts/public.inc"
%include "mod/structs/dev.inc"
%include "mod/consts/dev.inc"

%ifdef MOD_USE_PROFILER
extern mod_perf_ticks
%include "rtl/api/profiler.inc"
%endif

; Shortcut macros for easier access to nested structures

%define	params(var) params + mod_dev_params. %+ var
%define	set_api_fn(name, lbl) at mod_dev_api. %+ name, dd %+ (lbl)

; Printer control bits to select left/right channel for stereo LPT DAC

LPTST_CHN_LEFT	EQU 00000001b
LPTST_CHN_RIGHT	EQU 00000010b
LPTST_CHN_BOTH	EQU 00000011b


;------------------------------------------------------------------------------
; Set up the DAC output device.
;------------------------------------------------------------------------------
; -> AL - Output device type (MOD_DAC_*)
;    EBX - Pointer to mod_dev_params structure
;    CH.CL - Amplification in 8.8-bit fixed point format
;    EDX - Requested sample rate
; <- CF - Set if error
;    EAX - Error code if CF set or actual sample rate
;    EBX - Number of extra samples that will be generated at the end of each
;          sample (must reserve enough space) if no error
;    ECX - Number of extra samples that will be generated at the beginning of
;          each sample (must reserve enough space) if no error
;------------------------------------------------------------------------------

setup:
	push edx
	push esi
	push edi
	push ebx
	push ecx

	cld

	; Validate device type

	cmp al, MOD_DAC_LPTDUAL
	ja .unknown_device

	; Save parameters

	mov [dev_type], al
	mov [amplify], cx

	mov esi, ebx
	mov edi, params
	mov ecx, (mod_dev_params.strucsize + 3) / 4
	rep movsd

	mov ebx, [params(buffer_size)]
	mov [wanted_buf_size], ebx
	mov [wanted_smp_rate], edx

	call check_hw_caps
	mov [output_format], ah
	test ah, FMT_STEREO		; Check if device supports stereo
	jnz .log_config
	mov byte [params(stereo_mode)], MOD_PAN_MONO

.log_config:

	%if (LOG_LEVEL >= LOG_INFO)

	; Log configuration

	cmp al, MOD_DAC_SPEAKER
	jne .check_lpt
	log LOG_INFO, {'Output device: Internal PC speaker', 13, 10}
	jmp .alloc_buffer

.check_lpt:
	cmp al, MOD_DAC_LPT
	jne .check_lptst
	log LOG_INFO, {'Output device: Mono LPT DAC on port 0x{X16}', 13, 10}, [params(port)]
	jmp .alloc_buffer

.check_lptst:
	cmp al, MOD_DAC_LPTST
	jne .check_lptdual
	log LOG_INFO, {'Output device: Stereo LPT DAC on port 0x{X16}', 13, 10}, [params(port)]
	jmp .alloc_buffer

.check_lptdual:
	cmp al, MOD_DAC_LPTDUAL
	jne .alloc_buffer
	log LOG_INFO, {'Output device: Dual LPT DACs on port 0x{X16} and 0x{X16}', 13, 10}, [params(port)], [params(port + 2)]

	%endif

.alloc_buffer:

	; Allocate memory for the output buffer.

	mov edx, -1
	test byte [params(flags)], MOD_FLG_SR_CHG
	jnz .get_hw_caps
	mov edx, [wanted_smp_rate]	; Sample rate change not allowed

.get_hw_caps:
	mov al, [dev_type]
	call check_hw_caps		; Enforce sample rate limits
	call calc_sample_rate		; Get actual sample rate
	mov ebx, [wanted_buf_size]
	call calc_buf_size		; Get buffer size in samples
	mov [params(buffer_size)], eax

	mov ebx, eax
	shl ebx, 3			; 32-bit stereo buffer for SW wavetable
	lea ecx, [ebx + ebx * 2]	; Triple buffering
	mov al, PMI_MEM_HI_LO
	call pmi(mem_alloc)
	jc .error
	mov [buffer_addr], eax

	log LOG_DEBUG, {'Allocated {u} bytes for output device buffer at 0x{X}', 13, 10}, ecx, eax

	call calc_sample_rate
	mov [sample_rate], edx		; Save actual sample rate

	; Setup wavetable

	mov al, [params(interpolation)]
	mov ah, [params(stereo_mode)]
	mov bx, [amplify]
	xor ecx, ecx			; Render to output buffer directly
	mov dl, [output_format]
	mov dh, [params(initial_pan)]
	cmp ah, MOD_PAN_MONO		; Set output format to mono when mono
	jne .setup_wt			; playback was requested
	and dl, ~FMT_CHANNELS
	or dl, FMT_MONO
	mov [output_format], dl

.setup_wt:
	call mod_swt_setup
	jc .error
	mov [amplify], bx
	mov ebx, eax

	; Done

	add esp, 8			; Discard EBX and ECX from stack
	mov eax, [sample_rate]
	clc

.exit:
	pop edi
	pop esi
	pop edx
	ret

.unknown_device:
	mov eax, MOD_ERR_DEV_UNK

.error:
	pop ecx
	pop ebx
	stc
	jmp .exit


;------------------------------------------------------------------------------
; Get the maximum capabilities of the DAC variant.
;------------------------------------------------------------------------------
; -> AL - DAC device type
;    EDX - Requested sample rate
; <- AH - Bitstream format supported by the device
;         Note: FMT_STEREO will always be set if the device is capable of
;         stereo playback, regardless of wanted output stereo mode
;    EDX - Maximum supported sample rate for device
;------------------------------------------------------------------------------

check_hw_caps:
	cmp edx, 8000			; Force minimum 8 kHz samplerate (which
	jae .check_sample_rate_max	; will still sound awful)
	mov edx, 8000

.check_sample_rate_max:
	cmp al, MOD_DAC_SPEAKER
	je .check_sample_rate_max_speaker
	cmp edx, 44100			; Limit maximum to 44.1 kHz for LPT DACs
	jbe .set_output_format
	mov edx, 44100
	jmp .set_output_format

.check_sample_rate_max_speaker:
	cmp edx, 29000			; Limit maximum to 29 kHz for PC speaker
	jbe .set_output_format		; Higher values would reduce bitdepth
	mov edx, 29000			; too much

.set_output_format:
	mov ah, FMT_UNSIGNED		; Set output bitstream format flags
	or ah, FMT_8BIT
	cmp al, MOD_DAC_LPTST
	je .stereo_device
	cmp al, MOD_DAC_LPTDUAL
	je .stereo_device
	or ah, FMT_MONO
	jmp .done

.stereo_device:
	or ah, FMT_STEREO

.done:
	ret


;------------------------------------------------------------------------------
; Calculate actual sample rate and PIT timer reload value (rate).
;------------------------------------------------------------------------------
; -> EDX - Requested sample rate
; <- EDX - Actual playback sample rate of the device
;    [pit_rate] - Set with SB/SB Pro time constant for programming
;------------------------------------------------------------------------------

calc_sample_rate:
	push eax
	push ebx

	call timer_calc_rate
	mov [pit_rate], bx

	mov edx, eax

	pop ebx
	pop eax
	ret


;------------------------------------------------------------------------------
; Calculate buffer size from microseconds to samples.
;------------------------------------------------------------------------------
; -> EBX - Requested buffer size in microseconds
;    EDX - Actual sample rate
; <- EAX - Buffer size in samples
;------------------------------------------------------------------------------

calc_buf_size:
	push ebx
	push edx

	mov eax, edx			; Convert microsec to buffer size
	cmp ebx, 1000000
	jae .limit_buffer_size
	mul ebx
	mov ebx, 1000000
	div ebx
	cmp edx, 500000			; Rounding
	setae dl
	movzx edx, dl
	add eax, edx

.check_buffer_size:
	cmp eax, 4096			; Maximum sane buffer size
	jbe .done

.limit_buffer_size:
	mov eax, 4096

.done:
	pop edx
	pop ebx
	ret


;------------------------------------------------------------------------------
; Shutdown the output device. No further playback is possible until the setup
; function is called again.
;------------------------------------------------------------------------------

shutdown:
	push eax

	log LOG_INFO, {'Shutting down DAC output device', 13, 10}

	; Shutdown wavetable

	call mod_swt_shutdown

	; Release memory

	mov eax, [buffer_addr]
	test eax, eax
	jz .done

	log {'Disposing output buffer at 0x{X}', 13, 10}, eax

	call pmi(mem_free)
	mov dword [buffer_addr], 0

.done:
	pop eax
	ret


;------------------------------------------------------------------------------
; Set the number of active channels.
;------------------------------------------------------------------------------
; -> AL - Number of channels
;------------------------------------------------------------------------------

set_channels:
	mov [num_channels], al
	call mod_swt_set_channels

	ret


;------------------------------------------------------------------------------
; Set the amplification level.
;------------------------------------------------------------------------------
; -> AH.AL - Requested audio amplification in 8.8 fixed point value
; <- AH.AL - Actual audio amplification level
;------------------------------------------------------------------------------

set_amplify:
	mov [amplify], ax
	call mod_swt_set_amplify
	mov [amplify], ax

	ret


;------------------------------------------------------------------------------
; Set stereo rendering mode.
;------------------------------------------------------------------------------
; -> AL - Stereo rendering mode (MOD_PAN_*)
; <- AL - New stereo rendering mode
;------------------------------------------------------------------------------

set_stereo_mode:
	push eax
	push ebx
	push edx

	mov ah, [params(stereo_mode)]
	cmp al, ah
	je .done

	cmp al, MOD_PAN_MONO
	sete dl				; DL: 1 if new mode is mono
	cmp ah, MOD_PAN_MONO
	sete dh				; DH: 1 if current mode is mono
	add dl, dh			; DL: 1 if output format changes
	jz .set_wt			; Same output format

	test byte [params(flags)], MOD_FLG_FMT_CHG
	jz .done			; Format change not allowed
	mov ebx, eax			; BL: new stereo mode, BH: current
	mov edx, [wanted_smp_rate]
	mov al, [dev_type]
	call check_hw_caps
	cmp bl, MOD_PAN_MONO
	je .mono			; Switch to mono output
	test ah, FMT_STEREO		; Stereo not supported by card
	jz .done
	jmp .stereo			; Switch to stereo output

.mono:
	and ah, ~FMT_CHANNELS
	or ah, FMT_MONO

.stereo:
	call stop			; Stop playback
	mov [output_format], ah		; Update output format
	mov al, ah
	call mod_swt_set_output_format
	mov al, bl			; Set new stereo mode
	mov [params(stereo_mode)], bl
	call mod_swt_set_stereo_mode
	call play			; Restart playback
	jmp .done

.set_wt:
	mov [params(stereo_mode)], al
	call mod_swt_set_stereo_mode

.done:
	pop edx
	pop ebx
	mov al, [params(stereo_mode)]
	mov [esp], al
	pop eax
	ret


;------------------------------------------------------------------------------
; Get the nearest sample rate relative to current.
;------------------------------------------------------------------------------
; -> EAX - Steps relative to current sample rate (negative for lower, positive
;          for higher, zero to return current sample rate)
; <- EAX - Nearest available sample rate
;------------------------------------------------------------------------------

get_nearest_sample_rate:
	push ebx
	push ecx
	push edx

	xor edx, edx			; Snap to minimum sample rate
	cmp eax, -1000
	jle .check_caps
	dec edx				; Snap to maximum sample rate
	cmp eax, 1000
	jge .check_caps
	movzx ebx, word [pit_rate]	; EBX: current PIT reload value
	sub ebx, eax			; Lower reload -> higher sample rate
	js .check_caps			; Negative: snap to maximum sample rate

	; Calculate real interrupt rate for PIT reload value

	xor edx, edx
	mov eax, 1193182		; EAX: 1193182 (PIT osc. frequency)
	div ebx				; EAX: real interrupt rate
	mov ecx, ebx			; ECX: real interrupt rate / 2
	shr ecx, 1
	cmp edx, ecx			; Remainder > real interrupt rate / 2?
	setae dl
	movzx edx, dl			; EDX: 1 when yes, 0 otherwise
	add edx, eax

.check_caps:
	mov al, [dev_type]
	call check_hw_caps		; Limit rate to device capabilities
	call timer_calc_rate		; Get actual timer rate

	pop edx
	pop ecx
	pop ebx
	ret


;------------------------------------------------------------------------------
; Set sample rate.
;------------------------------------------------------------------------------
; -> EAX - Requested sample rate
; <- EAX - Actual sample rate
;------------------------------------------------------------------------------

set_sample_rate:
	push edx

	test byte [params(flags)], MOD_FLG_SR_CHG
	jz .done

	mov [wanted_smp_rate], eax	; Save current wanted sample rate
	mov edx, eax
	mov al, [dev_type]
	call check_hw_caps		; Get maximum sample rate
	call calc_sample_rate		; Get actual sample rate
	cmp edx, [sample_rate]
	je .done			; No change

	call stop			; Stop playback
	call play			; Restart playback

.done:
	pop edx
	mov eax, [sample_rate]
	ret


;------------------------------------------------------------------------------
; Start playback on the DAC device.
;------------------------------------------------------------------------------
; <- CF - Cleared
;------------------------------------------------------------------------------

play:
	push eax
	push ebx
	push ecx
	push edx
	push esi
	push edi
	push ebp

	; Initialize buffer variables

	mov edx, [wanted_smp_rate]	; Calculate actual sample rate
	mov al, [dev_type]
	call check_hw_caps
	call calc_sample_rate
	mov ebp, [sample_rate]		; EBP: previous sample rate
	mov [sample_rate], edx		; Save actual sample rate
	mov ebx, [wanted_buf_size]	; Calculate actual buffer size
	call calc_buf_size
	mov [params(buffer_size)], eax

	mov ebx, [params(buffer_size)]
	shl ebx, 3			; *8 (2 dwords per sample)
	mov [buffer_size], ebx

	mov byte [buffer_playprt], 0
	mov dword [play_sam_int], 0
	mov dword [play_sam_fr], 0
	mov eax, [buffer_addr]
	mov [buffer_pos], eax
	add eax, [buffer_size]
	mov [buffer_limit], eax
	mov byte [playing], 1

	; Calculate period -> SW wavetable speed conversion base

	mov ebx, [sample_rate]
	mov edx, 0x361
	mov eax, 0xf0f00000
	div ebx
	shr ebx, 1			; EBX: sample rate / 2
	cmp edx, ebx			; Remainder > sample rate / 2?
	setae dl
	movzx edx, dl			; EDX: 1 when yes, 0 otherwise
	add eax, edx
	mov [period_base], eax

	; Recalculate sample speed and tick rate when sample rate changed

	cmp ebp, [sample_rate]
	je .init_buffer
	mov eax, 0x0400
	xor ebx, ebx

.adjust_period_loop:
	mov ecx, [channel_period + ebx * 4]
	call set_mixer
	inc al
	inc ebx
	cmp al, MOD_MAX_CHANS
	jb .adjust_period_loop

	mov ebx, [tick_rate]
	call set_tick_rate

.init_buffer:

	; Pre-render into output buffer before starting playback

	mov byte [buffer_pending], BUF_READY
	mov byte [buffer_status], BUF_RENDER_1
	call render
	mov byte [buffer_status], BUF_RENDER_2
	call render
	mov byte [buffer_status], BUF_RENDER_3
	call render

	; Create speaker sample lookup table

	cmp byte [dev_type], MOD_DAC_SPEAKER
	jne .setup_irq
	xor ebx, ebx			; EBX: sample (0 - 255)
	movzx ecx, word [pit_rate]	; ECX: timer IRQ PIT rate (always 8-bit)
	cmp ecx, 64
	jbe .speakertab_loop
	mov ecx, 64

.speakertab_loop:
	mov al, bl
	mul cl
	inc ah
	mov [speakertab + ebx], ah
	inc bl
	jnz .speakertab_loop

.setup_irq:

	; Setup and install IRQ 0 handler

	xor al, al
	call pmi(get_irq_hndlr)
	mov [irq0_prev_handler], edx
	mov [irq0_prev_handler + 4], cx
	movzx edx, word [params(port)]	; EDX, EDI: parallel port DAC I/O ports
	movzx edi, word [params(port + 2)]

	; Since all DAC device rely on the PC's timer interrupt, each device
	; has its own dedicated IRQ 0 handler with code optimized to be as fast
	; as possible since it's called at the frequency of the sample rate.

	cmp byte [dev_type], MOD_DAC_SPEAKER
	je .start_speaker
	cmp byte [dev_type], MOD_DAC_LPTST
	je .start_lpt_dac_stereo
	cmp byte [dev_type], MOD_DAC_LPTDUAL
	je .start_lpt_dac_dual
	cmp byte [dev_type], MOD_DAC_LPT
	je .start_lpt_dac

.start_speaker:

	; Setup PC speaker

	in al, 0x61			; Turn on speaker
	or al, 0x03
	out 0x61, al
	mov al, 0x90			; Set PIT channel 2 to mode 0
	out 0x43, al
	mov al, 0x01
	out 0x42, al
	mov word [speaker_irq0_player_segment], ds
	mov edx, speaker_irq0_handler
	jmp .setup_irq_handler

.start_lpt_dac_stereo:

	; Setup stereo LPT DAC. This device is attached to a single parallel
	; port and the currently output channel is switched via strobe and/or
	; auto linefeed pins. See LPTST_CHN_* constants for printer control
	; values.

	add edx, 2
	in al, dx
	mov [lpt_prn_ctrl], al
	test byte [output_format], FMT_STEREO
	jz .start_lpt_dac_stereo_mono
	mov word [lpt_dac_stereo_irq0_player_segment], ds
	mov [lpt_dac_stereo_irq0_ctrl_port], edx
	mov edx, lpt_dac_stereo_irq0_handler
	jmp .setup_irq_handler

.start_lpt_dac_stereo_mono:

	; Stereo LPT DAC with forced mono output. Output same sample on both
	; channels.

	mov word [lpt_dac_stereo_mono_irq0_player_segment], ds
	mov [lpt_dac_stereo_mono_irq0_ctrl_port], edx
	mov edx, lpt_dac_stereo_mono_irq0_handler
	jmp .setup_irq_handler

.start_lpt_dac_dual:

	; Setup dual LPT DAC. This requires two parallel ports with a mono
	; 8-bit DAC connected to each. Device on first port is left channel and
	; device on second port is right channel.

	test byte [output_format], FMT_STEREO
	jz .start_lpt_dac_dual_mono
	mov word [lpt_dac_dual_irq0_player_segment], ds
	mov [lpt_dac_dual_irq0_port1], edx
	mov [lpt_dac_dual_irq0_port2a], edi
	mov [lpt_dac_dual_irq0_port2b], edi
	mov edx, lpt_dac_dual_irq0_handler
	jmp .setup_irq_handler

.start_lpt_dac_dual_mono:

	; Dual LPT DAC with forced mono output

	mov word [lpt_dac_dual_mono_irq0_player_segment], ds
	mov [lpt_dac_dual_mono_irq0_port1], edx
	mov [lpt_dac_dual_mono_irq0_port2a], edi
	mov [lpt_dac_dual_mono_irq0_port2b], edi
	mov edx, lpt_dac_dual_mono_irq0_handler
	jmp .setup_irq_handler

.start_lpt_dac:

	; Mono (single) LPT DAC

	mov word [lpt_dac_irq0_player_segment], ds
	mov [lpt_dac_irq0_port1], edx
	mov edx, lpt_dac_irq0_handler

.setup_irq_handler:
	xor al, al			; AL might be destroyed above
	mov cx, cs
	call pmi(set_irq_hndlr)

	; Set the rate of the timer interrupt

	mov word [pit_tick_count], 0
	mov bx, [pit_rate]
	call timer_set_rate

	; Enable IRQ 0

	xor cl, cl
	call irq_enable

.exit:
	clc
	pop ebp
	pop edi
	pop esi
	pop edx
	pop ecx
	pop ebx
	pop eax
	ret


;------------------------------------------------------------------------------
; Stop playback on the DAC device.
;------------------------------------------------------------------------------
; <- CF - Cleared
;------------------------------------------------------------------------------

stop:
	mov byte [playing], 0

	push eax
	push ebx
	push ecx
	push edx

	; Restore the rate of the timer

	call timer_reset_rate

	; Uninstall IRQ 0 handler

	xor al, al
	mov cx, [irq0_prev_handler + 4]
	mov edx, [irq0_prev_handler]
	call pmi(set_irq_hndlr)

	; Reset state

	mov word [pit_tick_count], 0

	cmp byte [dev_type], MOD_DAC_SPEAKER
	jne .stop_dac_lptst

	; Restore speaker state

	in al, 0x61			; Turn off speaker
	and al, 0xfc
	out 0x61,al
	mov al, 0xb6			; Reset PIT channel 2 to square wave
	out 0x43, al
	xor al, al
	out 0x42, al
	out 0x42, al
  	jmp .done

.stop_dac_lptst:
	cmp byte [dev_type], MOD_DAC_LPTST
	jne .done

	; Restore LPT printer controls for stereo LPT DAC

	mov dx, [params(port)]
	add dx, 2
	mov al, [lpt_prn_ctrl]
	out dx, al

.done:
	clc
	pop edx
	pop ecx
	pop ebx
	pop eax
	ret


;------------------------------------------------------------------------------
; Set the volume, panning and playback speed of a channel.
;------------------------------------------------------------------------------
; -> AL - Channel
;    AH - Mask bits
;         bit 0: Set volume to BL
;         bit 1: Set panning (balance) to BH
;         bit 2: Set speed to CX
;    BL - Volume (0 - 64)
;    BH - Panning (0 - 255)
;    ECX - Playback note periods
;------------------------------------------------------------------------------

	align 4

set_mixer:
	test ah, 0x04
 	jz mod_swt_set_mixer

	; Convert MOD period to playback speed if speed must be set for the
	; wavetable mixer.

	push ecx
	push edx

	xor edx, edx			; Save current period for channel
	mov dl, al
	mov [channel_period + edx * 4], ecx

	push eax
	xor eax, eax
	test ecx, ecx			; Guard against division by zero hangs
	setz al
	add ecx, eax
	xor edx, edx
	mov eax, [period_base]
	and ecx, 0xffff
	div ecx
	shr ecx, 1			; ECX: period / 2
	cmp edx, ecx			; Remainder > period / 2?
	setae dl
	movzx edx, dl			; EDX: 1 when yes, 0 otherwise
	add eax, edx
	mov edx, eax
	shr eax, 16
	mov ecx, eax			; ECX.DX: playback speed
	pop eax

	call mod_swt_set_mixer

	pop edx
	pop ecx
	ret


;------------------------------------------------------------------------------
; Set the playroutine callback tick rate.
;------------------------------------------------------------------------------
; -> EBX - Number of playroutine ticks per minute
;------------------------------------------------------------------------------

	align 4

set_tick_rate:
	push eax
	push ebx
	push edx

	mov [tick_rate], ebx		; Save current tick rate

	; Calculate number of samples between player ticks

	mov eax, [sample_rate]
	mov edx, eax
	shl eax, 6
	shl edx, 2
	sub eax, edx			; EAX: sample rate * 60
	mov edx, eax
	shr edx, 16
	shl eax, 16			; EDX:EAX: sample rate * 60 * 65536
	and ebx, 0xffff
	div ebx

	mov ebx, eax
	shr ebx, 16
	shl eax, 16			; EBX.EAX: samples between ticks
	mov [play_tickr_int], ebx
	mov [play_tickr_fr], eax

	pop edx
	pop ebx
	pop eax
	ret


;------------------------------------------------------------------------------
; Render channels into the output buffer.
;------------------------------------------------------------------------------
; <- Destroys everything except segment registers
;------------------------------------------------------------------------------

	align 4

render:
	%ifdef MOD_USE_PROFILER
	call profiler_get_counter
	push eax
	%endif
	mov al, BUF_RENDERING
	xchg al, byte [buffer_status]
	cmp al, BUF_RENDERING
	je .rendering			; BUF_RENDERING: already rendering audio
	jb .noop			; BUF_READY: nothing to render
	cmp byte [playing], 1		; Not playing, don't render
	jne .exit

	; Initialize state

	push dword 0			; Update channel_info by tick counter
	push eax

	mov edx, [params(buffer_size)]	; EDX: number of samples to render
	mov ebx, [play_sam_int]		; EBX: samples until playroutine tick
	mov edi, [buffer_addr]
	cmp al, BUF_RENDER_1
	je .loop_render
	mov esi, [buffer_size]		; 2nd part of buffer
	add edi, esi
	cmp al, BUF_RENDER_2
	je .loop_render
	add edi, esi			; 3rd part of buffer

	; Render samples to the output audio buffer
	; EBX: number of samples until next playroutine tick
	; ECX: number of samples to render by software wavetable in current pass
	; EDX: number of samples to render into output audio buffer
	; EDI: linear address of output audio buffer position to render into

.loop_render:

	; Call playroutine tick when necessary

	test ebx, ebx
	jnz .calc_render_count

	push ebx
	push ecx
	push edx
	push edi
	call mod_playroutine_get_position
	movzx ebp, dl			; EBP: current tick
	call mod_playroutine_tick
	pop edi
	pop edx
	pop ecx
	pop ebx

	mov eax, [esp]			; Restore AL from stack
	test ebp, ebp
	jz .main_tick			; Force channel_info update on main tick
	cmp dword [esp + 4], 0
	ja .skip_channel_info

.main_tick:
	call update_channel_info
	inc dword [esp + 4]		; Increase channel_info tick update

.skip_channel_info:
	mov eax, [play_tickr_fr]
	add [play_sam_fr], eax
	adc ebx, 0
	add ebx, [play_tickr_int]

.calc_render_count:

	; Determine number of samples to render in this pass

	mov ecx, edx			; ECX: number of samples to render
	cmp ecx, ebx			; Don't render past playroutine tick
	jb .render_swt
	mov ecx, ebx

.render_swt:

	; Render channels using software wavetable

	push ebx
	push ecx
	push edx
	call mod_swt_render_direct
	pop edx
	pop ecx
	pop ebx

	; Calculate number of samples left to render

	lea edi, [edi + ecx * 8]
	sub ebx, ecx
	sub edx, ecx
	jnz .loop_render

	pop eax
	pop ebp				; EBP: channel_info update by tick ctr

	; Output buffer completely rendered

	mov [play_sam_int], ebx		; Update samples until playroutine tick
	call update_buffer_position
	test ebp, ebp
	jnz .noop
	call update_channel_info	; Update channel_info when no tick

.noop:

	; Done rendering or nothing to do (no part of the buffer needs new audio
	; data)

	mov al, BUF_READY
	xchg al, [buffer_pending]
	mov [buffer_status], al

.exit:
	%ifdef MOD_USE_PROFILER
	call profiler_get_counter
	pop ebx
	sub eax, ebx
	add [mod_perf_ticks], eax
	%endif
	ret

.rendering:
	mov al, [buffer_pending]
	cmp al, BUF_RENDER_1
	jb .exit
	call update_buffer_position
	jmp .exit


;------------------------------------------------------------------------------
; Return information about output device.
;------------------------------------------------------------------------------
; -> ESI - Pointer to buffer receiving mod_channel_info structures
; <- ESI - Filled with data
;------------------------------------------------------------------------------

get_info:
	push eax
	push ecx

	; Buffer info

	mov eax, [sample_rate]
	mov [esi + mod_output_info.sample_rate], eax
	mov eax, [buffer_addr]
	mov [esi + mod_output_info.buffer_addr], eax
	mov eax, [buffer_size]
	lea eax, [eax + eax * 2]	; Triple buffering
	mov [esi + mod_output_info.buffer_size], eax
	mov eax, [buffer_pos]
	sub eax, [buffer_addr]
	mov [esi + mod_output_info.buffer_pos], eax

.format:

	; Calculate buffer format, always 2 channel 16-bit dword signed (same
	; as software wavetable render buffer format), but only left channel
	; used when output device is mono

	mov cl, [output_format]
	and cl, FMT_CHANNELS
	cmp cl, FMT_STEREO
	je .stereo
	mov byte [esi + mod_output_info.buffer_format], MOD_BUF_1632BIT | MOD_BUF_2CHNL | MOD_BUF_INT
	jmp .done

.stereo:
	mov byte [esi + mod_output_info.buffer_format], MOD_BUF_1632BIT | MOD_BUF_2CHN | MOD_BUF_INT

.done:
	pop ecx
	pop eax
	ret


;------------------------------------------------------------------------------
; Return current MOD playback position.
;------------------------------------------------------------------------------
; -> ESI - Pointer to buffer receiving mod_position_info structures
; <- ESI - Filled with data
;------------------------------------------------------------------------------

get_position:
	push ecx
	push esi
	push edi

	mov edi, esi
	xor esi, esi
	cmp byte [buffer_playprt], 1
	jb .done
	mov esi, mod_position_info.strucsize
	je .done
	add esi, esi

.done:
	add esi, position_info
	mov ecx, (mod_position_info.strucsize) / 4
	rep movsd

	pop edi
	pop esi
	pop ecx
	ret


;------------------------------------------------------------------------------
; Update song position information for a specific buffer part.
;------------------------------------------------------------------------------
; -> AL - Buffer part number (BUF_RENDER_n)
;------------------------------------------------------------------------------

update_buffer_position:
	push esi

	xor esi, esi			; Save playback position for this buffer
	cmp al, BUF_RENDER_2
	jb .get_position
	mov esi, mod_position_info.strucsize
	je .get_position
	add esi, esi

.get_position:
	add esi, position_info
	call mod_playroutine_get_position_info

	pop esi
	ret


;------------------------------------------------------------------------------
; Return current MOD channel info.
;------------------------------------------------------------------------------
; -> ESI - Pointer to buffer receiving mod_channel_info structures
; <- ESI - Filled with data
;------------------------------------------------------------------------------

get_channel_info:
	push ecx
	push esi
	push edi

	mov edi, esi
	mov ecx, (mod_channel_info.strucsize) / 4
	movzx esi, byte [num_channels]
	imul ecx, esi			; ECX: channel_info[] size
	xor esi, esi
	cmp byte [buffer_playprt], 1
	jb .done
	mov esi, mod_channel_info.strucsize * MOD_MAX_CHANS
	je .done
	add esi, esi

.done:
	add esi, channel_info
	rep movsd

	pop edi
	pop esi
	pop ecx
	ret


;------------------------------------------------------------------------------
; Update channel information for a specific buffer part.
;------------------------------------------------------------------------------
; -> AL - Buffer part number (BUF_RENDER_n)
;------------------------------------------------------------------------------

update_channel_info:
	push esi

	xor esi, esi			; Save channel_info for this buffer
	cmp al, BUF_RENDER_2
	jb .get_info
	mov esi, mod_channel_info.strucsize * MOD_MAX_CHANS
	je .get_info
	add esi, esi

.get_info:
	add esi, channel_info
	call mod_playroutine_get_channel_info
	call mod_swt_get_mixer_info

	pop esi
	ret


;------------------------------------------------------------------------------
; Reset all wavetable channels. Called on playback init by the playroutine and
; on song rewind.
;------------------------------------------------------------------------------

reset_channels:
	push eax
	push ecx
	push edx
	push edi

	mov dh, [params(initial_pan)]	; Reset software wavetable
	call mod_swt_reset_channels

	xor eax, eax			; Clear saved period values
	mov ecx, MOD_MAX_CHANS
	mov edi, channel_period
	rep stosd

	pop edi
	pop edx
	pop ecx
	pop eax
	ret


;==============================================================================
; DAC playback timer interrupt handlers.
;==============================================================================

;------------------------------------------------------------------------------
; Macro to push registers onto the stack at IRQ 0 entry.
;------------------------------------------------------------------------------

%macro	irq0_start 0

	push eax
	push edx
	push esi
	push ds

	cld

%endmacro


;------------------------------------------------------------------------------
; Macro to restore registers from the stack and return from the interrupt.
;------------------------------------------------------------------------------

%macro	irq0_exit 0

	pop ds
	pop esi
	pop edx
	pop eax
	iret

%endmacro


;------------------------------------------------------------------------------
; Send the end of interrupt signal to the interrupt controller and call the
; original IRQ 0 handler at the standard 18.2 Hz rate.
;------------------------------------------------------------------------------
; -> %1 - Jump target when ready or 0 to exit IRQ 0
; <- Destroys AL and DX
;------------------------------------------------------------------------------

%macro	irq0_eoi 1

	mov dx, [pit_rate]		; Call old handler if internal tick
	add [pit_tick_count], dx	; counter overflows 16-bit
	jc %%call_prev_handler

	irq_pic_eoi 0			; Destroys AL

	%if (%1 = 0)			; Exit IRQ 0 or jump to target label
	irq0_exit
	%else
	jmp %1
	%endif

	align 16

%%call_prev_handler:
	call prev_irq0_handler		; Call previous handler

	%if (%1 = 0)			; Exit IRQ 0 or jump to target label
	irq0_exit
	%else
	jmp %1
	%endif

%endmacro


;------------------------------------------------------------------------------
; Flip buffer if end is reached.
;------------------------------------------------------------------------------
; -> ESI - Current buffer position
;------------------------------------------------------------------------------

%macro	advance_buffer 0

	; Flip buffer if end is reached

	cmp esi, [buffer_limit]
	jae toggle_buffer

%endmacro


;------------------------------------------------------------------------------
; Call the original IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

prev_irq0_handler:
	pushfd
	call 0x1234:0x12345678
	irq0_prev_handler EQU $ - 6
	ret


;------------------------------------------------------------------------------
; PC speaker IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

speaker_irq0_handler:
	irq0_start

	; DS: player instance segment

	mov ax, 0x1234
	speaker_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov eax, [esi]
	add eax, 0x8080			; Convert to unsigned
	add esi, 8
	test eax, 0xffff0000
	jnz .clip			; Clipping
	xor edx, edx
	mov dl, ah
	mov al, [speakertab + edx]
	out 0x42, al
	mov [buffer_pos], esi

	advance_buffer
	irq0_eoi 0

	align 16

.clip:
	xor edx, edx
	cmp eax, 0
	setg dl				; AL: 1 if positive clip, else 0
	neg dl				; AL: 255 if positive clip, else 0
	mov al, [speakertab + edx]
	out 0x42, al
	mov [buffer_pos], esi

	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Mono LPT DAC IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

lpt_dac_irq0_handler:
	irq0_start

	mov ax, 0x1234
	lpt_dac_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov eax, [esi]
	mov edx, 0x12345678
	lpt_dac_irq0_port1 EQU $ - 4
	add eax, 0x8080			; Convert to unsigned
	add esi, 8
	test eax, 0xffff0000
	jnz .clip			; Clipping
	mov [buffer_pos], esi
	mov al, ah
	out dx, al

	advance_buffer
	irq0_eoi 0

	align 16

.clip:
	cmp eax, 0
	setg al				; AL: 1 if positive clip, else 0
	mov [buffer_pos], esi
	neg al				; AL: 255 if positive clip, else 0
	out dx, al

	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Stereo LPT DAC output IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

lpt_dac_stereo_irq0_handler:
	irq0_start

	mov ax, 0x1234
	lpt_dac_stereo_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov edx, 0x12345678
	lpt_dac_stereo_irq0_ctrl_port EQU $ - 4

	; Select DAC left channel

	mov al, LPTST_CHN_LEFT
	out dx, al
	add esi, 8
	sub edx, 2

	; Output left channel sample

	mov eax, [esi - 8]		; Left channel sample
	mov [buffer_pos], esi
	mov esi, [esi - 4]		; Right channel sample
	add eax, 0x8080			; Convert to unsigned
	add esi, 0x8080
	test eax, 0xffff0000
	jnz .clip_left			; Clipping
	mov al, ah
	out dx, al

	; Select DAC right channel

	add edx, 2
	mov al, LPTST_CHN_RIGHT
	out dx, al
	sub edx, 2

	; Output right channel sample

	mov eax, esi
	test esi, 0xffff0000
	jnz .clip_right			; Clipping
	mov al, ah
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0

	align 16

.clip_left:
	cmp eax, 0
	setg al				; AL: 1 if positive clip, else 0
	neg al				; AL: 255 if positive clip, else 0
	out dx, al

	; Select DAC right channel

	add edx, 2
	mov al, LPTST_CHN_RIGHT
	out dx, al
	sub edx, 2

	; Output right channel sample

	mov eax, esi
	test esi, 0xffff0000
	jnz .clip_right			; Clipping
	mov al, ah
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0

	align 16

.clip_right:
	cmp esi, 0
	setg al				; AL: 1 if positive clip, else 0
	neg al				; AL: 255 if positive clip, else 0
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Stereo LPT DAC mono output IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

lpt_dac_stereo_mono_irq0_handler:
	irq0_start

	mov ax, 0x1234
	lpt_dac_stereo_mono_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov eax, [esi]
	mov edx, 0x12345678
	lpt_dac_stereo_mono_irq0_ctrl_port EQU $ - 4
	add eax, 0x8080			; Convert to unsigned
	add esi, 8
	test eax, 0xffff0000
	jnz .clip			; Clipping

	; Output same sample to both channels

	mov al, LPTST_CHN_LEFT
	mov [buffer_pos], esi
	out dx, al
	sub edx, 2
	mov al, ah
	out dx, al
	mov al, LPTST_CHN_RIGHT
	add edx, 2
	out dx, al
	mov al, ah
	out dx, al

	advance_buffer
	irq0_eoi 0

	align 16

.clip:
	cmp eax, 0
	setg ah				; AH: 1 if positive clip, else 0
	mov [buffer_pos], esi
	neg ah				; AH: 255 if positive clip, else 0

	; Output same sample to both channels

	mov al, LPTST_CHN_LEFT		; Output same sample to both channels
	mov [buffer_pos], esi
	out dx, al
	sub edx, 2
	mov al, ah
	out dx, al
	mov al, LPTST_CHN_RIGHT
	add edx, 2
	out dx, al
	mov al, ah
	out dx, al

	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Dual LPT DAC output IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

lpt_dac_dual_irq0_handler:
	irq0_start

	mov ax, 0x1234
	lpt_dac_dual_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov edx, 0x1234
	lpt_dac_dual_irq0_port1 EQU $ - 4
	add esi, 8
	mov eax, [esi - 8]		; Left channel sample
	mov [buffer_pos], esi
	mov esi, [esi - 4]		; Right channel sample
	add eax, 0x8080			; Convert to unsigned
	add esi, 0x8080
	test eax, 0xffff0000
	jnz .clip_left			; Clipping
	mov al, ah
	out dx, al

	mov eax, esi
	mov edx, 0x1234
	lpt_dac_dual_irq0_port2a EQU $ - 4
	test esi, 0xffff0000
	jnz .clip_right			; Clipping
	mov al, ah
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0

	align 16

.clip_left:
	cmp eax, 0
	setg al				; AL: 1 if positive clip, else 0
	neg al				; AL: 255 if positive clip, else 0
	out dx, al

	mov edx, 0x1234
	lpt_dac_dual_irq0_port2b EQU $ - 4
	mov eax, esi
	test esi, 0xffff0000
	jnz .clip_right			; Clipping
	mov al, ah
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0

	align 16

.clip_right:
	cmp esi, 0
	setg al				; AL: 1 if positive clip, else 0
	neg al				; AL: 255 if positive clip, else 0
	out dx, al

	mov esi, [buffer_pos]
	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Dual LPT DAC forced mono output IRQ 0 handler.
;------------------------------------------------------------------------------

	align 16

lpt_dac_dual_mono_irq0_handler:
	irq0_start

	mov ax, 0x1234
	lpt_dac_dual_mono_irq0_player_segment EQU $ - 2
	mov ds, ax

	; Output next sample

	mov esi, [buffer_pos]
	mov edx, 0x1234
	lpt_dac_dual_mono_irq0_port1 EQU $ - 4
	mov eax, [esi]
	add esi, 8
	add eax, 0x8080			; Convert to unsigned
	test eax, 0xffff0000
	jnz .clip			; Clipping
	mov [buffer_pos], esi
	mov al, ah
	out dx, al			; Left channel DAC

	mov edx, 0x1234
	lpt_dac_dual_mono_irq0_port2a EQU $ - 4
	out dx, al			; Right channel DAC (same sample)

	advance_buffer
	irq0_eoi 0

	align 16

.clip:
	cmp eax, 0
	setg al				; AL: 1 if positive clip, else 0
	mov [buffer_pos], esi
	neg al				; AL: 255 if positive clip, else 0
	out dx, al			; Left channel DAC

	mov edx, 0x1234
	lpt_dac_dual_mono_irq0_port2b EQU $ - 4
	out dx, al			; Right channel DAC (same sample)

	advance_buffer
	irq0_eoi 0


;------------------------------------------------------------------------------
; Toggles and renders samples into the output audio buffer when the currently
; played part of the triple buffer reaches its end.
;------------------------------------------------------------------------------
; <- Destroys AH and DX
;------------------------------------------------------------------------------

toggle_buffer_render:

	; Jumping here from toggle_buffer / .reset_buffer. Must be defined in
	; advance, otherwise the macro throws an error.
	; -> AH: new buffer status

	cmp byte [buffer_status], BUF_RENDERING
	je .render_pending

	; Render into update pending buffer part

	push eax
	push ebx
	push ecx
	push edi
	push ebp
	push es
	mov ax, ds
	mov es, ax			; ES: flat memory model data selector
	sti				; Enable interrupts (important!)
	call render			; Render audio into output buffer
	cli				; Disable interrupts
	pop es
	pop ebp
	pop edi
	pop ecx
	pop ebx
	pop eax

	; Update pending buffer part unless a render was already in progress

	cmp byte [buffer_status], BUF_READY
	jne .exit
	mov byte [buffer_status], ah
	mov al, ah
	call update_buffer_position

.exit:
	irq0_exit

.render_pending:
	mov byte [buffer_pending], ah

	irq0_exit

toggle_buffer:

	; End of buffer reached, play next part of the triple buffer

	mov ah, [buffer_playprt]
	inc ah
	cmp ah, 2
	ja .reset_buffer		; Re-init to first part
	mov [buffer_playprt], ah	; Continue to 2nd/3rd part
	mov edx, [buffer_size]
	add [buffer_limit], edx		; Adjust buffer upper limit for playback
	add ah, BUF_RENDER_1 - 1	; Target render buffer: playing part - 1
	irq0_eoi toggle_buffer_render

.reset_buffer:

	; Wrap back to first part of the buffer

	mov byte [buffer_playprt], 0
	mov edx, [buffer_addr]
	mov [buffer_pos], edx
	add edx, [buffer_size]
	mov [buffer_limit], edx		; Buffer upper limit: end of 1st part
	mov ah, BUF_RENDER_3		; Target render buffer: 3rd part
	irq0_eoi toggle_buffer_render


;==============================================================================
; Data area
;==============================================================================

section .data

		; Output device API jump table

global mod_dev_dac_api
mod_dev_dac_api	istruc mod_dev_api
		set_api_fn(setup, setup)
		set_api_fn(shutdown, shutdown)
		set_api_fn(upload_sample, mod_swt_upload_sample)
		set_api_fn(free_sample, mod_swt_free_sample)
		set_api_fn(set_channels, set_channels)
		set_api_fn(set_amplify, set_amplify)
		set_api_fn(set_interpol, mod_swt_set_interpolation)
		set_api_fn(set_stereomode, set_stereo_mode)
		set_api_fn(play, play)
		set_api_fn(stop, stop)
		set_api_fn(set_tick_rate, set_tick_rate)
		set_api_fn(set_mixer, set_mixer)
		set_api_fn(set_sample, mod_swt_set_sample)
		set_api_fn(render, render)
		set_api_fn(get_chn_info, get_channel_info)
		set_api_fn(get_info, get_info)
		set_api_fn(get_position, get_position)
		set_api_fn(reset_channels, reset_channels)
		set_api_fn(set_samplerate, set_sample_rate)
		set_api_fn(get_nearest_sr, get_nearest_sample_rate)
		iend

num_channels	db 0			; Number of active channels

section .bss

position_info	resb mod_position_info.strucsize * 3
channel_info	resb mod_channel_info.strucsize * MOD_MAX_CHANS * 3
params		resd (mod_dev_params.strucsize + 3) / 4
period_base	resd 1			; Period to speed conversion base
wanted_smp_rate	resd 1			; Requested sample rate
sample_rate	resd 1			; Actual playback sample rate
wanted_buf_size	resd 1			; Wanted buffer size in microseconds
buffer_addr	resd 1			; Linear address of output buffer
buffer_size	resd 1			; Size of the output buffer
buffer_limit	resd 1			; End of current playing buffer
buffer_pos	resd 1			; Buffer playback position
channel_period	resd MOD_MAX_CHANS	; Current period for each channel
tick_rate	resd 1			; Current playroutine tick rate

play_tickr_int	resd 1			; Number of samples between player ticks
play_tickr_fr	resd 1			; Fraction part of the above
play_sam_int	resd 1			; Number of samples until next tick
play_sam_fr	resd 1			; Fraction part of the above
amplify		resw 1			; Output amplification

pit_rate	resw 1			; IRQ 0 rate
pit_tick_count	resw 1			; Counter for old IRQ 0 handler callback

buffer_playprt	resb 1			; Which of the double buffers is playing
buffer_status	resb 1			; Flag to indicate need for rendering
buffer_pending	resb 1			; Pending render into buffer
dev_type	resb 1			; Output DAC device type
output_format	resb 1			; Output bitstream format
lpt_prn_ctrl	resb 1			; Old LPT printer controls byte value
playing		resb 1			; Flag for playback ongoing
speakertab	resb 256		; PC speaker PWM conversion lookup table
