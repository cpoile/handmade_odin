// Started from: https://paste.odin-lang.org/1vf8aridw and then fixed

package dsound

import "base:intrinsics"
import "core:dynlib"
import "core:fmt"
import win32 "core:sys/windows"

CreateProc :: #type proc "std" (
	device: ^win32.GUID,
	dsObject: ^^DirectSound,
	unknownOuter: ^win32.IUnknown,
) -> win32.HRESULT

DSoundDLL :: "dsound.dll"

WAVE_FORMAT_PCM :: 1

DSSCL_PRIORITY :: 0x00000002

DSBCAPS_PRIMARYBUFFER :: 0x00000001
DSBCAPS_CTRLVOLUME :: 0x00000080
DSBCAPS_GETCURRENTPOSITION2 :: 0x00010000
DSBCAPS_GLOBALFOCUS :: 0x00008000

DSBPLAY_LOOPING :: 0x00000001

CooperativeLevel :: enum u32 {
	Normal       = 1,
	Priority     = 2,
	Exclusive    = 3,
	WritePrimary = 4,
}

BufferCaps :: enum u32 {
	PrimaryBuffer         = 0x0000_0001, // 1 << 0
	Static                = 0x0000_0002, // 1 << 1
	LocalHardware         = 0x0000_0004, // 1 << 2
	LocalSoftware         = 0x0000_0008, // 1 << 3
	Control3d             = 0x0000_0010, // 1 << 4
	ControlFrequency      = 0x0000_0020, // 1 << 5
	ControlPan            = 0x0000_0040, // 1 << 6
	ControlVolume         = 0x0000_0080, // 1 << 7
	ControlPositionNotify = 0x0000_0100, // 1 << 8
	ControlFx             = 0x0000_0200, // 1 << 9
	StickyFocus           = 0x0000_0400, // 1 << 10
	GlobalFocus           = 0x0000_0800, // 1 << 11
	GetCurrentPosition2   = 0x0000_1000, // 1 << 12
	Mute3dAtMaxDistance   = 0x0000_2000, // 1 << 13
	LocationDefer         = 0x0000_4000, // 1 << 14
	TruePlayPosition      = 0x0000_8000, // 1 << 15
}

WaveFormatTags :: enum u16 {
	Unknown = 0,
	Pcm     = 1,
}

Buffer :: struct {
	using bvtbl: ^BufferVtbl,
}

BufferVtbl :: struct {
	using uvtbl:        win32.IUnknown_VTable,
	getCaps:            #type proc "std" (this: ^Buffer, caps: ^BufferCapabilities) -> win32.HRESULT,
	getCurrentPosition: #type proc "std" (
		this: ^Buffer,
		currentPlayCursor, currentWriteCursor: ^win32.DWORD,
	) -> win32.HRESULT,
	getFormat:          #type proc "std" (
		this: ^Buffer,
		format: ^WaveFormatEx,
		sizeAllocated: win32.DWORD,
		sizeWritten: ^win32.DWORD,
	) -> win32.HRESULT,
	getVolume:          #type proc "std" (this: ^Buffer, volume: ^i32) -> win32.HRESULT,
	getPan:             #type proc "std" (this: ^Buffer, pan: ^i32) -> win32.HRESULT,
	getFrequency:       #type proc "std" (this: ^Buffer, frequency: ^win32.DWORD) -> win32.HRESULT,
	getStatus:          #type proc "std" (this: ^Buffer, status: ^win32.DWORD) -> win32.HRESULT,
	initialize:         #type proc "std" (
		this: ^Buffer,
		dsObj: ^DirectSound,
		description: ^BufferDescription,
	) -> win32.HRESULT,
	lock:               #type proc "std" (
		this: ^Buffer,
		offset, bytes: win32.DWORD,
		audioPtr1: ^rawptr,
		audioBytes1: ^win32.DWORD,
		audioPtr2: ^rawptr,
		audioBytes2: ^win32.DWORD,
		flags: win32.DWORD,
	) -> win32.HRESULT,
	play:               #type proc "std" (
		this: ^Buffer,
		reserved1: win32.DWORD,
		priority, flags: win32.DWORD,
	) -> win32.HRESULT,
	setCurrentPosition: #type proc "std" (this: ^Buffer, position: win32.DWORD) -> win32.HRESULT,
	setFormat:          #type proc "std" (this: ^Buffer, format: ^WaveFormatEx) -> win32.HRESULT,
	setVolume:          #type proc "std" (this: ^Buffer, volume: i32) -> win32.HRESULT,
	setPan:             #type proc "std" (this: ^Buffer, pan: i32) -> win32.HRESULT,
	setFrequency:       #type proc "std" (this: ^Buffer, frequency: win32.DWORD) -> win32.HRESULT,
	stop:               #type proc "std" (buffer: ^Buffer) -> win32.HRESULT,
	unlock:             #type proc "std" (
		this: ^Buffer,
		audioPtr1: rawptr,
		audioBytes1: win32.DWORD,
		audioPtr2: rawptr,
		audioBytes2: win32.DWORD,
	) -> win32.HRESULT,
	restore:            #type proc "std" (buffer: ^Buffer) -> win32.HRESULT,
}

BufferCapabilities :: struct {
	size, flags:        win32.DWORD,
	bufferBytes:        win32.DWORD,
	unlockTransferRate: win32.DWORD,
	playCpuOverhead:    win32.DWORD,
}

BufferDescription :: struct {
	size, flags: win32.DWORD,
	bufferBytes: win32.DWORD,
	reserved:    win32.DWORD,
	waveFormat:  ^WaveFormatEx,
	algorithm3d: win32.GUID,
}

DirectSound :: struct {
	using dsvtbl: ^DirectSoundVtbl,
}

DirectSoundVtbl :: struct {
	using uvtbl:          win32.IUnknownVtbl,
	createSoundBuffer:    #type proc "std" (
		this: ^DirectSound,
		description: ^BufferDescription,
		buffer: ^^Buffer,
		unknownOuter: ^win32.IUnknown,
	) -> win32.HRESULT,
	getCaps:              #type proc "std" (this: ^DirectSound, caps: ^DirectSoundCapabilities) -> win32.HRESULT,
	duplicateSoundBuffer: #type proc "std" (
		this: ^DirectSound,
		bufferOriginal: ^Buffer,
		bufferDuplicate: ^^Buffer,
	) -> win32.HRESULT,
	setCooperativeLevel:  #type proc "std" (this: ^DirectSound, window: win32.HWND, level: win32.DWORD) -> win32.HRESULT,
	compact:              #type proc "std" (this: ^DirectSound) -> win32.HRESULT,
	getSpeakerConfig:     #type proc "std" (this: ^DirectSound, speakerConfig: ^win32.DWORD) -> win32.HRESULT,
	setSpeakerConfig:     #type proc "std" (this: ^DirectSound, speakerConfig: win32.DWORD) -> win32.HRESULT,
	initialize:           #type proc "std" (this: ^DirectSound, device: ^win32.GUID) -> win32.HRESULT,
}

DirectSoundCapabilities :: struct {
	size, flags, minSecondarySampleRate, maxSecondarySampleRate, primaryBuffers, maxHwMixingAllBuffers, maxHWMixingStaticBuffers, maxHwMixingStreamingBuffers, freeHwMixingAllBuffers, freeHWMixingStaticBuffers, freeHwMixingStreamingBuffers, maxHw3dAllBuffers, maxHW3dStaticBuffers, maxHw3dStreamingBuffers, freeHw3dAllBuffers, freeHW3dStaticBuffers, freeHw3dStreamingBuffers, totalHwMemoryBytes, freeHwMemoryBytes, maxContiguousFreeHwMemoryBytes, unlockTransferRateHwBuffers, playCpuOverheadHwBuffers, reserved1, reserved2: win32.DWORD,
}

WaveFormat :: struct {
	formatTag, channels:                 win32.WORD,
	samplesPerSecond, avgBytesPerSecond: win32.DWORD,
	blockAlign:                          win32.WORD,
}

WaveFormatEx :: struct {
	formatTag, channels:                 win32.WORD,
	samplesPerSecond, avgBytesPerSecond: win32.DWORD,
	blockAlign:                          win32.WORD,
	bitsPerSample, size:                 win32.WORD,
}

load :: proc(window: win32.HWND, sec_buffer: ^^Buffer, bufferSize: u32, samplesPerSecond: u32) {
	dsoundLib: dynlib.Library = ---
	ok: bool

	dsoundLib, ok = dynlib.load_library(DSoundDLL)
	if !ok {
		win32.OutputDebugStringA("DirectSound, LoadLibraryW failed.\n")
		return
	}

	sym: rawptr = ---
	sym, ok = dynlib.symbol_address(dsoundLib, "DirectSoundCreate")
	if !ok || sym == nil {
		win32.OutputDebugStringA("DirectSound, GetProcAddress failed.\n")
		return
	}
	create := cast(CreateProc)sym

	dsObj: ^DirectSound = ---
	if hresult := create(nil, &dsObj, nil); hresult < 0 {
		_, _, code := win32.DECODE_HRESULT(hresult)
		fmt.eprintf("Error in DirectSoundCreate: code 0x%X\n", code)
		return
	}

	caps: DirectSoundCapabilities
	assert(size_of(caps) == 96)

	if hresult := dsObj->setCooperativeLevel(window, u32(CooperativeLevel.Priority)); hresult < 0 {
		fmt.eprintf("Error in setCooperativeLevel: code 0x%X\n", hresult)
		return
	}

	primaryBuffer: ^Buffer = ---
	pBufferDesc: BufferDescription = {
		size  = size_of(BufferDescription),
		flags = u32(BufferCaps.PrimaryBuffer),
	}

	if hresult := dsObj->createSoundBuffer(&pBufferDesc, &primaryBuffer, nil); hresult < 0 {
		_, _, code := win32.DECODE_HRESULT(hresult)
		fmt.eprintf("Error in createSoundBuffer: code 0x%X\n", code)
		return
	}

	ch, bps: u16 = 2, 16 // 2-channel, 16-bit audio
	block := ch * bps / 8
	waveFormat: WaveFormatEx = {
		formatTag         = u16(WaveFormatTags.Pcm),
		channels          = ch,
		samplesPerSecond  = samplesPerSecond,
		bitsPerSample     = bps,
		blockAlign        = block,
		avgBytesPerSecond = u32(block) * samplesPerSecond,
		size              = 0,
	}

	if hresult := primaryBuffer->setFormat(&waveFormat); hresult < 0 {
		_, _, code := win32.DECODE_HRESULT(hresult)
		fmt.eprintf("Error in setFormat: code 0x%X\n", code)
		return
	}

	s: cstring = "DirectSound: Primary buffer format set!\n"
	fmt.printf(string(s))
	win32.OutputDebugStringA(s)

	sBufferDesc: BufferDescription = {
		size        = size_of(BufferDescription),
		flags       = DSBCAPS_CTRLVOLUME | DSBCAPS_GETCURRENTPOSITION2,
		bufferBytes = u32(bufferSize),
		waveFormat  = &waveFormat,
	}
	if hresult := dsObj->createSoundBuffer(&sBufferDesc, sec_buffer, nil); hresult < 0 {
		_, _, code := win32.DECODE_HRESULT(hresult)
		fmt.eprintf("Error in createSoundBuffer: code 0x%X\n", code)
		return
	}

	s = "DirectSound: Secondary buffer successfully created!"
	fmt.printf(string(s))
	win32.OutputDebugStringA(s)
}
