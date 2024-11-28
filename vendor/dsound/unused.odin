// Released as Public Domain, Attribution appreciated but not required, Jon Lipstate
// Retrieved 2024-11-26 from https://gist.githubusercontent.com/jon-lipstate/3d3a21646b6b2d8d5cda5e848d45da84/raw/81efd882725c6dfed1ce6904bc28ad55bf0659f8/dsound.odin

package dsound


import "core:dynlib"
import "core:fmt"
import win32 "core:sys/windows"
import "vendor:directx/dxgi"

when false {

IDirectSound :: struct {
	using lpVtbl: ^IDirectSoundVtbl,
}

IDirectSoundVtbl :: struct {
	using iunknown_vtable: dxgi.IUnknown_VTable,
	CreateSoundBuffer:     proc "stdcall" (
		this: ^IDirectSound,
		pcDSBufferDesc: ^DSBUFFERDESC,
		ppDSBuffer: ^^IDirectSoundBuffer,
		pUnkOuter: rawptr,
	) -> win32.HRESULT,
	GetCaps:               proc "stdcall" (this: ^IDirectSound, pDSCaps: ^DSCAPS) -> win32.HRESULT,
	DuplicateSoundBuffer:  proc "stdcall" (
		this: ^IDirectSound,
		pDSBufferOriginal: ^IDirectSoundBuffer,
		ppDSBufferDuplicate: ^^IDirectSoundBuffer,
	) -> win32.HRESULT,
	SetCooperativeLevel:   proc "stdcall" (this: ^IDirectSound, hwnd: win32.HWND, dwLevel: win32.DWORD) -> win32.HRESULT,
	Compact:               proc "stdcall" (this: ^IDirectSound) -> win32.HRESULT,
	GetSpeakerConfig:      proc "stdcall" (this: ^IDirectSound, pdwSpeakerConfig: ^win32.DWORD) -> win32.HRESULT,
	SetSpeakerConfig:      proc "stdcall" (this: ^IDirectSound, dwSpeakerConfig: win32.DWORD) -> win32.HRESULT,
	Initialize:            proc "stdcall" (this: ^IDirectSound, pcGuidDevice: ^win32.GUID) -> win32.HRESULT,
}

DSBUFFERDESC :: struct {
	dwSize:          win32.DWORD,
	dwFlags:         win32.DWORD,
	dwBufferBytes:   win32.DWORD,
	dwReserved:      win32.DWORD,
	lpwfxFormat:     ^WAVEFORMATEX,
	// #if DIRECTSOUND_VERSION >= 0x0700
	guid3DAlgorithm: win32.GUID,
	// #endif
}

WAVEFORMATEX :: struct {
	wFormatTag:      win32.WORD, /* format type */
	nChannels:       win32.WORD, /* number of channels (i.e. mono, stereo...) */
	nSamplesPerSec:  win32.DWORD, /* sample rate */
	nAvgBytesPerSec: win32.DWORD, /* for buffer estimation */
	nBlockAlign:     win32.WORD, /* block size of data */
	wBitsPerSample:  win32.WORD, /* number of bits per sample of mono data */
	cbSize:          win32.WORD, /* the count in bytes of the size of */
	/* extra information (after cbSize) */
}

IDirectSoundBuffer :: struct {
	using lpVtbl: ^IDirectSoundBufferVtbl,
}
IDirectSoundBufferVtbl :: struct {
	using iunknown_vtable: dxgi.IUnknown_VTable,
	GetCaps:               proc "stdcall" (this: ^IDirectSoundBuffer, pDSBufferCaps: ^DSBCAPS) -> win32.HRESULT, //LPDSBCAPS
	GetCurrentPosition:    proc "stdcall" (
		this: ^IDirectSoundBuffer,
		pdwCurrentPlayCursor: ^win32.DWORD,
		pdwCurrentWriteCursor: ^win32.DWORD,
	) -> win32.HRESULT,
	GetFormat:             proc "stdcall" (
		this: ^IDirectSoundBuffer,
		pwfxFormat: ^WAVEFORMATEX,
		dwSizeAllocated: win32.DWORD,
		pdwSizeWritten: ^win32.DWORD,
	) -> win32.HRESULT,
	GetVolume:             proc "stdcall" (this: ^IDirectSoundBuffer, plVolume: ^win32.LONG) -> win32.HRESULT,
	GetPan:                proc "stdcall" (this: ^IDirectSoundBuffer, plPan: ^win32.LONG) -> win32.HRESULT,
	GetFrequency:          proc "stdcall" (this: ^IDirectSoundBuffer, pdwFrequency: ^win32.DWORD) -> win32.HRESULT,
	GetStatus:             proc "stdcall" (this: ^IDirectSoundBuffer, pdwStatus: ^win32.DWORD) -> win32.HRESULT,
	Initialize:            proc "stdcall" (
		this: ^IDirectSoundBuffer,
		pDirectSound: ^IDirectSound,
		pcDSBufferDesc: ^DSBUFFERDESC,
	) -> win32.HRESULT,
	Lock:                  proc "stdcall" (
		this: ^IDirectSoundBuffer,
		dwOffset: win32.DWORD,
		dwBytes: win32.DWORD,
		ppvAudioPtr1: ^win32.LPVOID,
		pdwAudioBytes1: ^win32.DWORD,
		ppvAudioPtr2: ^win32.LPVOID,
		pdwAudioBytes2: ^win32.DWORD,
		dwFlags: win32.DWORD,
	) -> win32.HRESULT,
	Play:                  proc "stdcall" (
		this: ^IDirectSoundBuffer,
		dwReserved1: win32.DWORD,
		dwPriority: win32.DWORD,
		dwFlags: win32.DWORD,
	) -> win32.HRESULT,
	SetCurrentPosition:    proc "stdcall" (this: ^IDirectSoundBuffer, dwNewPosition: win32.DWORD) -> win32.HRESULT,
	SetFormat:             proc "stdcall" (this: ^IDirectSoundBuffer, pcfxFormat: ^WAVEFORMATEX) -> win32.HRESULT,
	SetVolume:             proc "stdcall" (this: ^IDirectSoundBuffer, lVolume: win32.LONG) -> win32.HRESULT,
	SetPan:                proc "stdcall" (this: ^IDirectSoundBuffer, lPan: win32.LONG) -> win32.HRESULT,
	SetFrequency:          proc "stdcall" (this: ^IDirectSoundBuffer, dwFrequency: win32.DWORD) -> win32.HRESULT,
	Stop:                  proc "stdcall" (this: ^IDirectSoundBuffer) -> win32.HRESULT,
	Unlock:                proc "stdcall" (
		this: ^IDirectSoundBuffer,
		pvAudioPtr1: win32.LPVOID,
		dwAudioBytes1: win32.DWORD,
		pvAudioPtr2: win32.LPVOID,
		dwAudioBytes2: win32.DWORD,
	) -> win32.HRESULT,
	Restore:               proc "stdcall" (this: ^IDirectSoundBuffer) -> win32.HRESULT,
}



DSCAPS :: struct {
	dwSize:                         win32.DWORD,
	dwFlags:                        win32.DWORD,
	dwMinSecondarySampleRate:       win32.DWORD,
	dwMaxSecondarySampleRate:       win32.DWORD,
	dwPrimaryBuffers:               win32.DWORD,
	dwMaxHwMixingAllBuffers:        win32.DWORD,
	dwMaxHwMixingStaticBuffers:     win32.DWORD,
	dwMaxHwMixingStreamingBuffers:  win32.DWORD,
	dwFreeHwMixingAllBuffers:       win32.DWORD,
	dwFreeHwMixingStaticBuffers:    win32.DWORD,
	dwFreeHwMixingStreamingBuffers: win32.DWORD,
	dwMaxHw3DAllBuffers:            win32.DWORD,
	dwMaxHw3DStaticBuffers:         win32.DWORD,
	dwMaxHw3DStreamingBuffers:      win32.DWORD,
	dwFreeHw3DAllBuffers:           win32.DWORD,
	dwFreeHw3DStaticBuffers:        win32.DWORD,
	dwFreeHw3DStreamingBuffers:     win32.DWORD,
	dwTotalHwMemBytes:              win32.DWORD,
	dwFreeHwMemBytes:               win32.DWORD,
	dwMaxContigFreeHwMemBytes:      win32.DWORD,
	dwUnlockTransferRateHwBuffers:  win32.DWORD,
	dwPlayCpuOverheadSwBuffers:     win32.DWORD,
	dwReserved1:                    win32.DWORD,
	dwReserved2:                    win32.DWORD,
}

DSBCAPS :: struct {
	dwSize:               win32.DWORD,
	dwFlags:              win32.DWORD,
	dwBufferBytes:        win32.DWORD,
	dwUnlockTransferRate: win32.DWORD,
	dwPlayCpuOverhead:    win32.DWORD,
}

}
