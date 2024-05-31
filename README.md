This is a 32-bit protected mode

MOD player library
==================

_for [PMI](https://github.com/a11599/pmi) applications_

- Optimized 16-bit mixers
- Variable amplification with clipping
- Various sample interpolation methods
- Stereo crossfade for hard panned (Amiga) MODs
- Multichannel support


Table of contents
-----------------

- [Features](#features)
  - [Supported formats](#supported-formats)
  - [Supported output devices](#supported-output-devices)
  - [Audio features](#audio-features)
- [API](#api)
  - [Jumpstart](#jumpstart)
  - [Setup functions](#setup-functions)
    - [`mod_sb_detect`](#mod_sb_detect)
    - [`mod_setup`](#mod_setup)
    - [`mod_shutdown`](#mod_shutdown)
  - [MOD file handling](#mod-file-handling)
    - [`mod_load`](#mod_load)
    - [`mod_unload`](#mod_unload)
  - [Playback control](#playback-control)
    - [`mod_play`](#mod_play)
    - [`mod_set_amplify`](#mod_set_amplify)
    - [`mod_set_interpolation`](#mod_set_interpolation)
    - [`mod_set_stereo_mode`](#mod_set_stereo_mode)
    - [`mod_set_position`](#mod_set_position)
    - [`mod_stop`](#mod_stop)
    - [`mod_render`](#mod_render)
  - [Information services](#information-services)
    - [`mod_get_info`](#mod_get_info)
    - [`mod_get_channel_info`](#mod_get_channel_info)
    - [`mod_get_output_info`](#mod_get_output_info)
    - [`mod_get_position`](#mod_get_position)
    - [`mod_get_position_info`](#mod_get_position_info)
    - [`mod_perf_ticks`](#mod_perf_ticks)
- [Configure and build](#configure-and-build)
  - [Changing compile time parameters](#changing-compile-time-parameters)
  - [Building a custom library version](#building-a-custom-library-version)


# Features

## Supported formats

- ProTracker MOD format (`M.K.`, `M!K!`, `FLT4`)
- 8-channel MOD formats (`OCTA`, `CD81`)
- 1-32 channel MOD formats (`TDZx`, `xCHN`, `xxCH`)
- ProTracker 2.3 effects
- Panning effects `8xx` and `E8x`

Not supported:
- Sound Tracker modules (15-instrument)
- MOD files without embedded samples
- Some uncommon Amiga-specific playback/ProTracker quirks such as sample swap
- Effects `E0x` (set filter) and `EFx` (funk it / invert loop)

## Supported output devices

- No sound (keeps the player running without actually playing anything)
- PC speaker up to 29 kHz sample rate
- LPT DAC variants (single, dual, stereo) up to 44.1 kHz sample rate
- Sound Blaster, Pro and 16 up to 22/44.1 kHz sample rate (depending on actual model)

## Audio features

- 2 extra octaves above/below standard ProTracker note range.
- Up to 32 channels (can be extended when necessary).
- 16-bit mixing all the way across the mixer chain.
- Variable output amplification between 0.0 - 4.0x.
- All-integer/fixed point mixer code (no FPU required).
- Stereo output (when supported by device) with hard panning (Amiga-style), 75% crossfade or real stereo supporting 8xx and E8x channel pan commands.
- Nearest neighbor / zero order hold interpolation (also referred to as no interpolation, although this is technically incorrect) for Amiga-like sound quality without multiplications in the audio mixer code.
- Fast 8-bit linear interpolation for Gravis Ultrasound-like sound quality without multiplications in the audio mixer code.
- High quality 16-bit trilinear interpolation (Jon Watte algorithm) with only 2 multiplications (4 in real stereo mode) per sample.

# API

The API is defined in `src\mod\api\mod.inc`. Most procedures return the carry flag (CF) set if the operation failed along with an error code in EAX. The error code may come from the MOD player itself or from a PMI. Possible error codes from the player are:

| value  | name              | description |
| ------ | ----------------- | ----------- |
| 0x0100 | `MOD_ERR_INVALID` | Invalid MOD file format (file corrupted, unsupported or not a MOD file). |
| 0x0101 | `MOD_ERR_DEV_UNK` | Unknown output device or output device type provided. |
| 0x0102 | `MOD_ERR_NB_CHN`  | MOD has too many or no channels (possibly corrupted file format). |
| 0x0103 | `MOD_ERR_STATE`   | The MOD player cannot process the operation in its current state (eg. `mod_load` was called before `mod_setup`.) |
| 0x0104 | `MOD_ERR_DEVICE`  | The output device is not responding to the initialization request. |

## Jumpstart

The bare minimum sequence for MOD playback:

- Call `mod_setup` to initialize the library
- Call `mod_load` to load the MOD file
- Call `mod_play` to start playback
- Call `mod_shutdown` to shutdown the library and stop playback

Link all `.obj` files of the MOD library produced by `wmake` or `wmake build=release` (see chapter on building the library) to the final executable. The library also requires the following runtime library modules from PMI to be linked to the final executable:

- `env_arg`
- `string`
- `irq`
- `timer`
- `systimer`
- `profiler` if `MOD_USE_PROFILER` is enabled in configuration
- `log` for the debug builds

For a complex example please refer to [tmodplay](https://github.com/a11599/tmodplay), a standalone DOS MOD player.

## Setup functions

### `mod_sb_detect`

Attempts to detect the presence of a Sound Blaster card by parsing the `BLASTER` environment variable.

Inputs:

- EBX: Pointer to `mod_dev_params` structure (see `mod_setup` for structure definition).

Outputs:
- CF: Set if a Sound Blaster card was not detected.
- AL: Device type when Sound Blaster was detected (see `MOD_SB_*` constants in `mod_setup`).
- EBX: `mod_dev_params` structure filled with card-specific `port`, `irq` and `dma` settings.

### `mod_setup`

Initialize the MOD player and selected output device.

Inputs:

- `AH`: Output device, see output device table constants below.
- `AL`: Output device type, see output device table constants below.
- `EBX`: Pointer to `mod_dev_params` structure.
- `CH.CL`: Initial amplification in 8.8 bit fixed point format. Refer to `mod_set_amplify` for details.
- `EDX`: Requested output mixing sample rate.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set) or actual output mixing sample rate.

Supported output devices:

| value | output device  | device type       | description |
| ----- | -------------- | ----------------- | ----------- |
| 0 / 0 | `MOD_OUT_NONE` | `MOD_NONE`        | Keeps the player running without rendering any audio output. |
| 1 / 0 | `MOD_OUT_DAC`  | `MOD_DAC_SPEAKER` | Mono 5.3 - 6 bit playback on the PC speaker. Maximum sample rate is 29 kHz. Fixed configuration, does not need `port`, `irq` or `dma` configuration in `mod_dev_params`. |
| 1 / 1 | `MOD_OUT_DAC`  | `MOD_DAC_LPT`     | Mono 8 bit playback on a parallel port D/A converter (Covox). Maximum sample rate is 44.1 kHz. Requires `port` to be specified in `mod_dev_params`. |
| 1 / 2 | `MOD_OUT_DAC`  | `MOD_DAC_LPTST`   | Stereo 8 bit playback on a stereo-on-1 parallel port D/A converter. Maximum sample rate is 44.1 kHz. Requires `port` to be specified in `mod_dev_params`. |
| 1 / 3 | `MOD_OUT_DAC`  | `MOD_DAC_LPTDUAL` | Stereo 8 bit playback on two parallel port D/A converters. Maximum sample rate is 44.1 kHz. Requires two I/O ports to be specified in `mod_dev_params.port`. |
| 2 / 0 | `MOD_OUT_SB`   | `MOD_SB_1`        | Mono 8 bit playback on original Sound Blaster (no auto-init DMA). Maximum sample rate is 22 kHz. Requires `port`, `irq` and `dma` to be set in `mod_dev_params.port`. |
| 2 / 1 | `MOD_OUT_SB`   | `MOD_SB_2`        | Mono 8 bit playback on Sound Blaster 2.0. Maximum sample rate is 44 kHz. Requires `port`, `irq` and `dma` to be set in `mod_dev_params.port`. |
| 2 / 2 | `MOD_OUT_SB`   | `MOD_SB_PRO`      | Stereo 8 bit playback on Sound Blaster Pro. Maximum sample rate is 22 kHz in stereo or 44 kHz in mono mode. Requires `port`, `irq` and `dma` to be set in `mod_dev_params.port`. |
| 2 / 3 | `MOD_OUT_SB`   | `MOD_SB_16`       | Stereo 16 bit playback on Sound Blaster 16. Maximum sample rate is 44.1 kHz. Requires `port`, `irq` and both 8-bit and 16-bit DMA channels in `dma` to be set in `mod_dev_params.port`. 8-bit and 16-bit `dma` may contain the same value (some clone cards may not support 16-bit DMA channels, set the 8-bit DMA channel number for the 16-bit DMA entry in this case). |

- `MOD_OUT_NONE` and `MOD_OUT_DAC` use the timer interrupt (IRQ 0) for audio playback or to keep the player running.
- `MOD_OUT_SB` uses the Sound Blaster's IRQ and a 16 or 8-bit DMA channel for audio playback and to keep the player running.
- For `MOD_DAC_LPTST`, the strobe and auto linefeed pins are used to select the output channel the following way:
  - Strobe (pin 1): output on left channel when high
  - Auto line feed (pin 14): output on right channel when high
  - Essentially the auto line feed pin is low when strobe is high and vice versa.

The `mod_dev_params` structure defines additional parameters for the output device:

| offset | name            | size  | description |
| ------ | --------------- | ----- | ----------- |
| 0x00   | `buffer_size`   | 4     | Requested size of the output buffer in microseconds. Refer to `mod_render` on details about how to set the buffer size to keep the MOD player from interrupting your rendering process. |
| 0x04   | `port`          | 2 x 2 | Base I/O port(s) of the device. |
| 0x08   | `irq`           | 2 x 1 | IRQ(s) used by the device. |
| 0x0a   | `dma`           | 2 x 1 | 8-bit (low) and 16-bit (high) DMA channels used by the device. |
| 0x0c   | `stereo_mode`   | 1     | Stereo panning mode for stereo output devices. See `MOD_PAN_*` constants below. |
| 0x0d   | `initial_pan`   | 1     | Set initial panning for real stereo mode. Set to `0x80` to pan all channels to center (mono) on start, `0x0` to hard pan left/right or any value in-between for crossfade panning. Actual panning will be changed by `8xx` and `E8x` MOD effects. |
| 0x0e   | `interpolation` | 1     | Set the initial interpolation method. See `MOD_IPOL_*` constants below. |
| 0x0f   | `flags`         | 1     | Player behavior control flags. See `MOD_FLG_*` constants below. |

The following values are supported for stereo panning mode on stereo output devices:

| value | name            | description |
| ----- | --------------- | ----------- |
| 0     | `MOD_PAN_MONO`  | Force mono output. |
| 1     | `MOD_PAN_HARD`  | Pan channels to hard left/right as on the Amiga. True to the original but not very enjoyable unless the MOD was especially crafted for hard panning. `MOD_PAN_MONO` or `MOD_PAN_CROSS` usually provide a more enjoyable listening experience for MODs that don't use panning effects. |
| 2     | `MOD_PAN_CROSS` | Pan channels to hard left/right and apply a 75% amplitude cross-mixing between channels. This is a nice compromise that adds some fake sense of space to the music with only minimal CPU overhead. |
| 3     | `MOD_PAN_REAL`  | Pan channels according to `8xx` and `E8x` effects in the MOD file. Channels are initially panned as specified in `mod_dev_params.initial_pan`. This uses significantly more CPU than the others (around 1.4x compared to hard panning). |

When mono playback is requested:

- `MOD_DAC_LPTST` and `MOD_DAC_LPTDUAL` will output the same sample on both channels/DACs.
- `MOD_SB_PRO` and `MOD_SB_16` are setup for mono playback.

The following values are available to select the interpolation method:

| value | name              | description |
| ----- | ----------------- | ----------- |
| 0     | `MOD_IPOL_NN`     | Nearest neighbor or zero-order hold or incorrectly also known as no interpolation. This method sustains the sample value until the next one and produces horrible aliasing artifacts. However, several MOD files - especially older ones with lower quality samples - rely on these artifacts and will sound dull with better interpolation methods. |
| 1     | `MOD_IPOL_LINEAR` | Fast 8-bit linear interpolation. This method generates samples in-between by using a simple weighted average. It is similar to the mixing quality of the Gravis Ultrasound, although that has 16-bit interpolation which reduces the noise level. It is a big step forward in quality that leaves some of the artifacts of nearest neighbor interpolation so that even old MODs can remain somewhat enjoyable. It uses about 2x CPU as nearest neighbor on a Pentium MMX. |
| 2     | `MOD_IPOL_WATTE`  | High quality 16-bit trilinear interpolation implementing Jon Watte's algorithm from Olli Niemitalo's "Polynomial Interpolators for High-Quality Resampling of Oversampled Audio" paper (deip.pdf). It does an excellent job to cut off aliasing artifacts while also preserving most frequencies at the passband, but can render MODs with low quality samples completely unenjoyable. It uses about 3.7x CPU as nearest neighbor on a Pentium MMX. |

The following flags are available for controlling player behavior:

| value | name              | description |
| ----- | ----------------- | ----------- |
| 0x01  | `MOD_FLG_FMT_CHG` | Enable on-the-fly bitstream format change during playback. This allows switching between mono and stereo output on devices where this results in a device reinitialization. The player will allocate a stereo output/render buffer for stereo output devices even when mono output is forced using `MOD_PAN_MONO`. |
| 0x02  | `MOD_FLG_SR_CHG`  | Enable on-the-fly sample rate changes during playback. The player will allocate an output/render buffer that is large enough to contain samples up to the highest supported sample rate of the device. |

These flags are for advanced player usage by standalone players. For normal embedded usage as a background music player in your application you usually don't need to set any of them.

### `mod_shutdown`

Shuts down the MOD playback system. Any pending playback is terminated and the sound device is deinitialized.

Inputs:

None.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).

## MOD file handling

### `mod_load`

Load a MOD file from disk to memory.

Inputs:

- `EBX`: File handle of the MOD opened for (at least) read access. The caller is responsible to open the file and set the current file pointer at the start of the MOD binary. (This is useful if the MOD is packaged along with other files for easier distribution.)

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).

The MOD will be loaded into extended memory when possible.

### `mod_unload`

Remove the previously loaded MOD file from the memory and release allocated memory blocks.

Inputs:

None.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).

## Playback control

### `mod_play`

Start playback of the currently loaded MOD file.

Inputs:

None.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).

### `mod_set_amplify`

Set amplification level between 0.0 - 4.0x. At level 4x, a single channel can saturate the entire output range and playback in multiple channels may cause severe clipping. Level 1.0x is a good default value which avoids most clipping even with multichannel MODs (at this level, a channel can only saturate up to 25% of the total output). Experiment with the music you want to play and set the amplification level accordingly so the volume remains constant throughout your application without producing clipping.

This function can be called before or during playback to change the output level. It does 16384 multiplications to recalculate the volume table, so be aware that it can take a while on low-end CPUs. The change becomes effective at the next audio rendering pass (~ 2 * render buffer size latency).

Inputs:

- `AH.AL`: Amplification as 8.8 bit fixed point number.

Outputs:

- `AH.AL`: Actual amplification level as 8.8 bit fixed point number.

Set AX to `0x0100` for 1x, `0x0180` for 1.5x `0x0200` for 2.0x amplification, and so on. Please refer to [Wikipedia](https://en.wikipedia.org/wiki/Fixed-point_arithmetic) if you are not familiar with fixed point artihmetics.

### `mod_set_interpolation`

Set the interpolation method. This function can be called before or during playback. The change becomes effective at the next audio rendering pass (~ 2 * render buffer size latency).

Inputs:

- `AL`: Sample interpolation method. See `MOD_IPOL_*` constants.

Outputs:

None.

### `mod_set_stereo_mode`

Set the stereo panning method for stereo output devices. The function does nothing if the device is mono. This function can be called before or during playback. The change becomes effective at the next audio rendering pass (~ 2 * render buffer size latency).

Switching between mono and stereo on DAC and Sound Blaster devices during playback is only possible when the `MOD_FLG_FMT_CHG` flag was set during device setup. On these devices, switching between mono and any stereo mode will flush the audio buffer and reinitialize the output device.

Inputs:

- `AL`: Stereo panning method. See `MOD_PAN_*` constants.

Outputs:

- `AL`: Actual stereo panning method (always `MOD_PAN_MONO` for mono devices).

### `mod_set_sample_rate`

Change the sample rate. This is only allowed on DAC and Sound Blaster devices if the `MOD_FLG_SR_CHG` flag was set during device setup. This operation will flush the audio buffer and reinitialize the output device.

Inputs:

- `EAX`: Requested new sample rate.

Outputs:

- `EAX`: Actual sample rate.

### `mod_get_nearest_sample_rate`

Get the closest sample rate relative to current sample rate for the selected output device. Some devices (all DACs, the original Sound Blaster and Pro) are limited to a limited set of possible sample rates.

For example, DAC devices which use the timer interrupt can sample at 44192 Hz or 42614 Hz, but not in between. When a sample rate is specified during device initialization or via `mod_set_sample_rate`, the device will use the nearest possible value. This is one step in the example, so if the current sample rate is 44192 Hz and this function is called with `EAX` = `-1`, the function will return `42614` in `EAX`.

Sound Blaster 16 in contrast can use any sample rate, so if the current sample rate is 44100 Hz and this function is called with `EAX` = `-1`, the function will return `44099` in `EAX`.

Inputs:

- `EAX`: Number of steps relative to current sample rate. Use negative amount for lower, positive for higher sample rates.

Outputs:

- `EAX`: Nearest possible sample rate.

### `mod_set_position`

Set the position of the playroutine. The change becomes effective at the next audio rendering pass (~ 2 * render buffer size latency). This function can be called during playback only.

Inputs:

- `AH`: Sequence entry number, starting at 0. Adjusted to last sequence entry when out of range.
- `AL`: Row within the current pattern, 0 - 63. Clipped to 63 if a higher value is given.
- `DL`: Set to 1 to stop playback of samples in channels before changing the position, 0 to keep them playing.

Outputs:

- `AH`: Actual sequence entry number, starting at 0.
- `AL`: Actual row within the current pattern, 0 - 63.

### `mod_stop`

Stop MOD playback.

Inputs:

None.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).

### `mod_render`

Render audio into the output buffer when needed. This function is provided so you can prevent the player from interrupting your application for a longer period of time.

Inputs:

None.

Outputs:

None.

The player uses triple buffering and renders audio into the buffer when a part has been played completely. This rendering can take a noticable amount of time (depending on number of channels, interpolation and stereo mode) and it can introduce jerkiness if it interrupts your render loop at an inconvenient time.

To prevent this from happening, follow the strategy below:

- Call `mod_render` in your render loop when the application finished all other important tasks.
- Set the buffer size so that it covers the time needed for the render loop plus audio rendering.

Applications where this matters usually run in a vsync-locked render loop. Let's assume you use 320x240 VGA resolution and you want to update the screen in each frame (targetting 60 fps).

- 320x240 runs at 60 Hz, so the MOD player buffer size should be set to 1 / 60 * 1000000 = 16667 microseconds. Actual refresh rates may vary, so to be safe, let's round it up to 17000 microseconds.
- In the render loop, once you are finished with other tasks (flipping, rendering, input processing), call `mod_render` to update the output buffer.
- Design the application so that it can sustain the target framerate on the targeted hardware.
- There will be a few frames when `mod_render` won't do anything, since the buffer is a bit larger, than a frame.
- If the render loop does not finish within the frame and the buffer gets exhausted, the player will interrupt your application and render within its interrupt handler, so audio won't stutter unless the CPU is underpowered for the song/mixer settings.

## Information services

### `mod_get_info`

Return information about the current MOD file. This function can be called when a MOD is loaded by the player.

Inputs:

None.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set) or linear address of `mod_info` structure.

The `mod_info` structure is static and depends only on the MOD currently loaded by the player. It can be freed by the caller using the `mem_free` PMI service when the data is no longer needed.

| offset | name            | size | description |
| ------ | --------------- | ---- | ----------- |
| 0x00   | `title`         | 21   | ASCIIZ title of the song. |
| 0x15   | `num_channels`  | 1    | Number of channels in the song. |
| 0x16   | `num_samples`   | 1    | Number of samples used by the song. |
| 0x17   | `length`        | 1    | Number of entries in the pattern sequence. |
| 0x18   | `num_patterns`  | 1    | Number of patterns in the song. |
| 0x19   | `restart_pos`   | 1    | Song restart position. |
| 0x1c   | `flags`         | 4    | Song flags (see `MOD_FLG_*` constants below) |
| 0x20   | `sequence_addr` | 4    | Linear address of 128-byte sequence entries. |
| 0x24   | `pattern_addr`  | 4    | Linear address of start of pattern data. |
| 0x28   | `samples`       | N    | Start of `mod_sample_info` entries for each sample of the MOD file. |

Structure of `mod_sample_info`:

| offset | name        | size | description |
| ------ | ----------- | ---- | ----------- |
| 0x00   | `name`      | 23   | ASCIIZ name of the sample. |
| 0x18   | `addr`      | 4    | Pointer to linear address of sample start. |
| 0x1c   | `length`    | 4    | Length of the sample in bytes. |
| 0x20   | `rpt_start` | 4    | Start offset of the sample loop (repeat) in bytes. Set to 0 when there is no loop. |
| 0x24   | `rpt_len`   | 4    | Length of the sample loop in bytes. Set to 0 when there is no loop. |

The player may not retain the original contents of the sample after the end of the loop (may overwrite memory with unrolled loop data or discard it since it is not necessary for playback).

### `mod_get_channel_info`

Return information on current MOD player channels. This function can be called during MOD playback. The information is captured for each render buffer and the one belonging to the currently played buffer is returned by this call.

Inputs:

- `ESI`: Pointer to memory area for an array of `mod_channel_info` data for each channel used by the MOD file. The buffer must be large enough to contain information for all channels (see `mod_info.num_channels`).

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).
- `ESI`: Populated with an array of `mod_channel_info` structures.

Each `mod_channel_info` structure contains the following data:

| offset | name             | size | description |
| ------ | ---------------- | ---- | ----------- |
| 0x00   | `period`         | 4    | Current playback MOD period * 16. MOD period is a number representing the playback speed of a sample on the Amiga. |
| 0x04   | `sample_pos_int` | 4    | Current playback position of the sample being played in the channel. |
| 0x08   | `sample_pos_fr`  | 2    | Current playback position fraction of the sample being played in the channel. `sample_pos_int` and `sample_pos_fr` form a 32.16 bit fixed point number representing the current sample position. |
| 0x0a   | `sample`         | 1    | Number of the sample being played in the channel, between 0 - 32. 0 means the channel is not playing anything. |
| 0x0b   | `volume`         | 1    | Volume of the sample currently being played, between 0 - 64. The volume is linear, 0 stands for silence and 64 for full volume. |
| 0x0c   | `pan`            | 1    | Current panning position of the channel, between 0 - 255, where 0 stands for full left and 255 stands for full right. |

When the output device is `MOD_OUT_NONE`, the `sample_pos_int` and `sample_pos_fr` members of the structure won't be updated since there is no actual audio rendering.

### `mod_get_output_info`

Get information about the output device's current status. This function can be called during MOD playback.

Inputs:

- `ESI`: Pointer to memory area for a `mod_output_info` structure.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).
- `ESI`: Populated with `mod_output_info` structure data.

When the output device is `MOD_OUT_NONE`, this function is not doing anything since there is no actual audio rendering.

The `mod_output_info` structure contains the following data:

| offset | name            | size | description |
| ------ | --------------- | ---- | ----------- |
| 0x00   | `sample_rate`   | 4    | Actual playback (output) sample rate. |
| 0x04   | `buffer_addr`   | 4    | Linear address of the output buffer. |
| 0x08   | `buffer_size`   | 4    | Size of the output buffer in bytes. |
| 0x0c   | `buffer_pos`    | 4    | Current playback position within the buffer. |
| 0x10   | `buffer_format` | 1    | Audio data / sample format within the buffer. See `MOD_BUF_*` constants below. |

The type of the output buffer is represented by the following values:

| value | name              | description |
| ----- | ----------------- | ----------- |
| 0x03  | `MOD_BUF_DEPTH`   | Bitmask to extract audio bitdepth from format byte. |
| 0x00  | `MOD_BUF_8BIT`    | 8-bit samples, 1 byte each. |
| 0x01  | `MOD_BUF_16BIT`   | 16-bit samples, 2 bytes each. |
| 0x02  | `MOD_BUF_1632BIT` | 16-bit samples, 4 bytes each, may overflow 16-bit range. |
| 0x0c  | `MOD_BUF_CHANNEL` | Bitmask to extract number of channels from format byte. |
| 0x00  | `MOD_BUF_1CHN`    | 1 channel (mono). |
| 0x04  | `MOD_BUF_2CHN`    | 2 channels (stereo). |
| 0x08  | `MOD_BUF_2CHNL`   | 2 channels, but only left channel contains audio data (mono). |
| 0x10  | `MOD_BUF_RANGE`   | Bitmask to extract sample data range from format byte. |
| 0x00  | `MOD_BUF_INT`     | Sample data is signed integer (-128 - 127 or -32768 - 32767). |
| 0x10  | `MOD_BUF_UINT`    | Sample data is unsigned integer (0 - 255 or 0 - 65535).

### `mod_get_position`

Return the current position of the playroutine. This can be off by several ticks, depending on the size of the render buffer. Use `mod_get_position_info` for a more accurate reading that accounts for the buffer. The purpose of this method is to get current information for relative position jumps via `mod_set_position`.

Inputs:

None.

Outputs:

- `AH`: Sequence entry number, starting at 0.
- `AL`: Row within the current pattern, 0 - 63.
- `DL`: Current tick within the row, starting at 0.

### `mod_get_position_info`

Get information about the song position currently played. This function can be called during MOD playback. The information is captured for each render buffer and the one belonging to the currently played buffer is returned by this call.

Inputs:

- `ESI`: Pointer to memory area for a `mod_position_info` structure.

Outputs:

- `CF`: Set if failed.
- `EAX`: Error code if failed (`CF` is set).
- `ESI`: Populated with `mod_position_info` structure data.

The `mod_position_info` structure contains the following data:

| offset | name       | size | description |
| ------ | ---------- | ---- | ----------- |
| 0x00   | `position` | 1    | Song position within the pattern sequence (0 - 127). |
| 0x01   | `pattern`  | 1    | Number of pattern being played (0 - 255). |
| 0x02   | `row`      | 1    | Row within pattern (0 - 63).
| 0x03   | `tick`     | 1    | Current tick within the row. |
| 0x04   | `speed`    | 1    | Number of ticks within a row. |
| 0x05   | `bpm`      | 1    | Beats per minute (32 - 255). |

### `mod_perf_ticks`

A 32-bit counter that increments by the number of performance ticks spent with audio mixing and playroutine handling. You can read and reset this at any time. Compare this with the amount of performance counter ticks that elapsed in a known timeframe to calculate the relative amount of time spent with MOD playback.


# Configure and build

## Changing compile time parameters

The MOD library supports a few compilation-time parameters defined in `src\mod\config.inc`.

- `MOD_USE_PROFILER`: Enables performance profiling of the audio mixer/MOD playroutine via PMI `profiler` library. Default value is `1`. The application must call `profiler_start` before starting MOD playback.

- `MOD_MAX_CHANS`: Set the maximum number of channels supported by the MOD player. Default value is `32`, maximum is `255`. This has no effect on CPU usage, but additional channels use a little amount of extra RAM (even if the MOD does not use these extra channels).

- `UNROLL_COUNT`: Number of samples rendered by the audio mixer at one shot. This has a direct impact on memory usage as it expands the generated code size significantly. The default value is `20` which seems to be the sweet spot. Since the audio mixer code also has self-modifying code, increasing the number of unrolls also adds overhead to the setup code which will negate the benefits of the unroll itself. You can reduce it down to about `4` if code size and memory usage is extremely important for your use case. The number of unrolls also has an impact on memory used for samples.

- `UNROLL_MAX_SPD`: Maximum sample playback speed which is supported by the unrolled audio mixer. Default value is `17` which is a safe value for all supported MOD notes and output sample rates. The maximum supported unroll speed also has an impact on memory used for samples.

- `LIN_IPOL_EXP`: Maximum linear interpolation oversampling exponent. The actual oversampling is 2 ^ `LIN_IPOL_EXP`. Default value is `5`, which results in 32x oversampling (2 ^ 5 = 32). This is enough for up to 46.4 kHz sample rate for all supported MOD notes. Keep in mind that each additional oversampling requires 1024 bytes of memory for the interpolation lookup table. You can reduce this value to `3` (8x oversampling) if you only want to play standard ProTracker MODs.

- `WATTE_IPOL_EXP`: Maximum oversampling exponent for Watte trilinear interpolation. The actual oversampling is 2 ^ `WATTE_IPOL_EXP`. Default value is `5`, which results in 32x oversampling (2 ^ 5 = 32). This is enough for up to 46.4 kHz sample rate for all supported MOD notes. Keep in mind that each additional oversampling requires 2 additional clock cycles on the 386 and 486 due to larger numbers being multiplied. You can reduce this value to `3` (8x oversampling) if you only want to play standard ProTracker MODs.

## Building a custom library version

The library can be built under DOS and Windows. The build uses the following toolchain:

- [NASM](https://www.nasm.us/) to compile assembly source code to linkable objects.
- [Open Watcom](http://www.openwatcom.org/) to make the project and link the executable binary.

The build toolchain is also available for Linux, but the build system only supports DOS and Windows.

Download and install the dependencies, then:

- Copy `makeinit.sam` to `makeinit` and set the following parameters:
  - `nasm_dir`: Path to directory containing nasm.exe (NASM binary).
  - `watcom_dir`: Path to directory containing Open Watcom platform-dependent binaries.
  - If both of them are added to system `PATH`, you don't need to create a `makeinit` file.
- Download [PMI](https://github.com/a11599/pmi), extract it into the same parent as of `mod` and run `wmake dist` in the PMI folder. The folder structure should look like this:

```
  |
  +-- pmi
  |   |
  |   +-- build
  |   +-- dist
  |   +-- emu
  |   +-- lib
  |   +-- src
  |       ...
  |
  +-- mod
      |
      +-- src
          ...
```

In the project root directory, run `wmake` to create a debug build to `build\debug\mod`. Run `wmake build=release` to create a release build to `build\release\mod`

The following `wmake` targets are also available (append after `wmake` or `wmake build=release`):

- `wmake clean`: Remove compiled binaries in `build\debug` or `build\release` directory.
- `wmake full`: Force a full recompilation (compilation by default is incremental, only changed source code is recompiled).
- `wmake dist`: Create a binary distribution package to `dist` directory.
