package main

import "../vendor/backtrace"
import "../vendor/dsound"
import "../vendor/odin-xinput/xinput"
import "base:intrinsics"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:math"
import "core:simd/x86"
import "core:strings"
import win32 "core:sys/windows"

// aliases
L :: intrinsics.constant_utf16_cstring
int2 :: [2]i32

// consts
SAMPLE_RATE: u32 : 44100
BYTES_PER_SAMPLE :: size_of(u16) * 2
BUFFER_SIZE :: SAMPLE_RATE * BYTES_PER_SAMPLE

Game :: struct {
	size: int2,
}

offscreen_buffer :: struct {
	BitmapInfo: win32.BITMAPINFO,
	memory:     [^]u8,
	width:      i32,
	height:     i32,
	pitch:      i32,
}

win32_window_dimensions :: struct {
	width:  i32,
	height: i32,
}

win32_sound_output :: struct {
	tone_hz:              f32,  // TODO: f32?
	volume:               i16,
	running_sample_index: u32,
	wave_period:          f32, // TODO: f32?
	tSine:                f32,
	latency_sample_count: u32,
}


global_running := true
GlobalBackBuffer: offscreen_buffer
secondary_buffer: ^dsound.Buffer

win32_fill_sound_buffer :: proc(sound_output: ^win32_sound_output, byte_to_lock, bytes_to_write: u32) {
	//  u16   u16     u16   u16    u16   u16
	// [left right] [left right] [left right]
	region1, region2: rawptr
	size1, size2: u32
	hr := secondary_buffer->lock(byte_to_lock, bytes_to_write, &region1, &size1, &region2, &size2, 0)
	if hr < 0 {
		//_, _, code := win32.DECODE_HRESULT(hr)
		//fmt.eprintf("Error in Lock: code 0x%X\n", code)
	} else {
		//fmt.eprintf("GOT LOCK!\n")
		sample_out := transmute([^]i16)region1
		region1_sample_count := size1 / BYTES_PER_SAMPLE
		for i in 0 ..< region1_sample_count {
			sine_val := math.sin_f32(sound_output.tSine)
			sample_value := i16(sine_val * f32(sound_output.volume))
			sample_out[0] = sample_value
			sample_out = sample_out[1:]
			sample_out[0] = sample_value
			sample_out = sample_out[1:]

			sound_output.tSine += 2.0 * math.PI / sound_output.wave_period
			sound_output.running_sample_index += 1
		}

		sample_out = transmute([^]i16)region2
		region2_sample_count := size2 / BYTES_PER_SAMPLE
		for i in 0 ..< region2_sample_count {
			sine_val := math.sin_f32(sound_output.tSine)
			sample_value := i16(sine_val * f32(sound_output.volume))
			sample_out[0] = sample_value
			sample_out = sample_out[1:]
			sample_out[0] = sample_value
			sample_out = sample_out[1:]

			sound_output.tSine += 2.0 * math.PI / sound_output.wave_period
			sound_output.running_sample_index += 1
		}
		if hr = secondary_buffer->unlock(region1, size1, region2, size2); hr < 0 {
			//_, _, code := win32.DECODE_HRESULT(hr)
			//fmt.eprintf("Error in Unlock: code 0x%X\n", code)
		}
	}
}

get_window_dimensions :: proc(window: win32.HWND) -> win32_window_dimensions {
	client_rect: win32.RECT
	win32.GetClientRect(window, &client_rect)
	return {client_rect.right - client_rect.left, client_rect.bottom - client_rect.top}
}

render_weird_gradient :: proc(xOffset: i32, yOffset: i32) {
	row := GlobalBackBuffer.memory
	for y in 0 ..< GlobalBackBuffer.height {
		pixel := transmute([^]u32)row
		for x in 0 ..< GlobalBackBuffer.width {
			//                   1  2  3  4
			// pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
			//     in register: xx RR GG BB  (bc it's little endian)
			bb := u8(x + xOffset)
			gg := u8(y + yOffset)
			pixel[0] = (u32(gg) << 8) | u32(bb)
			pixel = pixel[1:]
		}

		row = row[GlobalBackBuffer.pitch:]
	}
}

win32_resize_DIB_section :: proc(width: i32, height: i32) {
	if (GlobalBackBuffer.memory != nil) {win32.VirtualFree(GlobalBackBuffer.memory, 0, win32.MEM_RELEASE)}
	GlobalBackBuffer.width = width
	GlobalBackBuffer.height = height
	bytes_per_pixel :: 4
	GlobalBackBuffer.pitch = width * bytes_per_pixel

	// NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
	// bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
	// not the bottom left
	GlobalBackBuffer.BitmapInfo.bmiHeader.biSize = size_of(type_of(GlobalBackBuffer.BitmapInfo.bmiHeader))
	GlobalBackBuffer.BitmapInfo.bmiHeader.biWidth = width
	GlobalBackBuffer.BitmapInfo.bmiHeader.biHeight = -height
	GlobalBackBuffer.BitmapInfo.bmiHeader.biPlanes = 1
	GlobalBackBuffer.BitmapInfo.bmiHeader.biBitCount = 32
	GlobalBackBuffer.BitmapInfo.bmiHeader.biCompression = win32.BI_RGB

	bitmap_memory_size := uint((GlobalBackBuffer.width * GlobalBackBuffer.height) * bytes_per_pixel)
	GlobalBackBuffer.memory =
	transmute([^]u8)win32.VirtualAlloc(
		nil,
		bitmap_memory_size,
		win32.MEM_RESERVE | win32.MEM_COMMIT,
		win32.PAGE_READWRITE,
	)
}

win32_display_buffer_in_window :: proc(deviceContext: win32.HDC, destWidth: i32, destHeight: i32) {
	// TODO: aspect ratio correction
	win32.StretchDIBits(
		deviceContext,
		0,
		0,
		destWidth,
		destHeight,
		0,
		0,
		GlobalBackBuffer.width,
		GlobalBackBuffer.height,
		GlobalBackBuffer.memory,
		&GlobalBackBuffer.BitmapInfo,
		win32.DIB_RGB_COLORS,
		win32.SRCCOPY,
	)
}

win32_main_window_callback :: proc "system" (
	window: win32.HWND,
	message: u32,
	WParam: win32.WPARAM,
	LParam: win32.LPARAM,
) -> win32.LRESULT {
	using win32
	context = runtime.default_context()

	alt_is_down := false

	result: LRESULT
	switch message {
	case WM_CREATE:
		OutputDebugStringA("WM_CREATE\n")

	case WM_SIZE:
		OutputDebugStringA("WM_SIZE\n")

	case WM_DESTROY:
		global_running = false
		OutputDebugStringA("WM_DESTROY\n")

	case WM_SYSKEYDOWN, WM_SYSKEYUP, WM_KEYDOWN, WM_KEYUP:
		vk_code := WParam
		altDown := (LParam & (1 << 29)) != 0
		wasDown := (LParam & (1 << 30)) != 0
		isDown := (LParam & (1 << 31)) == 0
		if (isDown != wasDown) {
			switch vk_code {
			case VK_F4:
				if altDown {global_running = false}
			case 'W':
				OutputDebugStringA("W\n")
			case 'A':
				OutputDebugStringA("A\n")
			case 'R':
				OutputDebugStringA("R\n")
			case 'S':
				OutputDebugStringA("S\n")
			case 'Q':
				OutputDebugStringA("Q\n")
			case 'F':
				OutputDebugStringA("F\n")
			case VK_UP:
				OutputDebugStringA("up\n")
			case VK_DOWN:
				OutputDebugStringA("down\n")
			case VK_LEFT:
				OutputDebugStringA("left\n")
			case VK_RIGHT:
				OutputDebugStringA("Right\n")
			case VK_ESCAPE:
				OutputDebugStringA(fmt.ctprintf("Escape is down? %t was down? %t\n", isDown, wasDown))
			}
		}

	case WM_CLOSE:
		global_running = false
		OutputDebugStringA("WM_CLOSE\n")

	case WM_ACTIVATEAPP:
		OutputDebugStringA("WM_ACTIVATEAPP\n")

	case WM_PAINT:
		paint: PAINTSTRUCT
		device_context: HDC = BeginPaint(window, &paint)
		defer EndPaint(window, &paint)
		dims: win32_window_dimensions = get_window_dimensions(window)
		win32_display_buffer_in_window(device_context, dims.width, dims.height)

	case:
		result = DefWindowProcA(window, message, WParam, LParam)
	}

	return result
}

register_class :: proc(instance: win32.HINSTANCE) -> win32.ATOM {
	icon: win32.HICON = win32.LoadIconW(instance, win32.MAKEINTRESOURCEW(101))
	if icon == nil {icon = win32.LoadIconW(nil, win32.wstring(win32._IDI_APPLICATION))}
	if icon == nil {show_error_and_panic("Missing icon")}
	cursor := win32.LoadCursorW(nil, win32.wstring(win32._IDC_ARROW))
	if cursor == nil {show_error_and_panic("Missing cursor")}
	wcx := win32.WNDCLASSW {
		style         = win32.CS_HREDRAW | win32.CS_VREDRAW | win32.CS_OWNDC,
		lpfnWndProc   = win32_main_window_callback,
		hInstance     = instance,
		hIcon         = icon,
		hCursor       = cursor,
		lpszClassName = L("OdinMainClass"),
	}
	return win32.RegisterClassW(&wcx)
}

unregister_class :: proc(atom: win32.ATOM, instance: win32.HINSTANCE) {
	if atom == 0 {show_error_and_panic("atom is zero")}
	if !win32.UnregisterClassW(win32.LPCWSTR(uintptr(atom)), instance) {show_error_and_panic("UnregisterClassW")}
}

adjust_size_for_style :: proc(size: ^int2, dwStyle: win32.DWORD) {
	rect := win32.RECT{0, 0, size.x, size.y}
	if win32.AdjustWindowRect(&rect, dwStyle, false) {
		size^ = {i32(rect.right - rect.left), i32(rect.bottom - rect.top)}
	}
}

create_window :: #force_inline proc(instance: win32.HINSTANCE, atom: win32.ATOM, game: ^Game) -> win32.HWND {
	if atom == 0 {show_error_and_panic("atom is zero")}
	style :: win32.WS_OVERLAPPEDWINDOW
	pos := int2{i32(win32.CW_USEDEFAULT), i32(win32.CW_USEDEFAULT)}
	size := game.size
	adjust_size_for_style(&size, style)
	return win32.CreateWindowW(
		win32.LPCWSTR(uintptr(atom)),
		L("Handmade Hero"),
		style,
		pos.x,
		pos.y,
		size.x,
		size.y,
		nil,
		nil,
		instance,
		nil,
	)
}

main :: proc() {
	perf_counter_frequency: win32.LARGE_INTEGER
	win32.QueryPerformanceFrequency(&perf_counter_frequency)

	backtrace.register_segfault_handler()

	game := Game {
		size = {1280, 720},
	}

	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
	if (instance == nil) {show_error_and_panic("No instance")}
	atom := register_class(instance)
	if atom == 0 {show_error_and_panic("Failed to register window class")}
	//defer unregister_class(atom, instance)  // TODO: crashing, not sure why.

	windowHandle := create_window(instance, atom, &game)
	if windowHandle == nil {show_error_and_panic("Failed to create window")}
	win32.ShowWindow(windowHandle, win32.SW_SHOWDEFAULT)
	win32.UpdateWindow(windowHandle)

	win32_resize_DIB_section(game.size.x, game.size.y)

	// NOTE: since we specified CS_OWNDC, we can just get one device context and use it
	// forever because we are not sharing it with anyone.
	deviceContext := win32.GetDC(windowHandle)

	// NOTE: graphics test
	xOffset: i32 = 0
	yOffset: i32 = 0

	// NOTE: sound test
	sound_output := win32_sound_output {
		tone_hz              = 261,
		volume               = 10000,
	}
	sound_output.wave_period = f32(SAMPLE_RATE) / sound_output.tone_hz
	sound_output.latency_sample_count = SAMPLE_RATE/20

	dsound.load(windowHandle, &secondary_buffer, BUFFER_SIZE, SAMPLE_RATE)
	win32_fill_sound_buffer(&sound_output, 0, sound_output.latency_sample_count * BYTES_PER_SAMPLE)
	if hr := secondary_buffer->play(0, 0, dsound.DSBPLAY_LOOPING); hr < 0 {
		_, _, code := win32.DECODE_HRESULT(hr)
		fmt.eprintf("Error in Play: code 0x%X\n", code)
		return
	}

	last_counter: win32.LARGE_INTEGER
	last_cycle_count := x86._rdtsc()
	win32.QueryPerformanceCounter(&last_counter)

	message: win32.MSG
	for (global_running) {
		if win32.PeekMessageA(&message, nil, 0, 0, win32.PM_REMOVE) {
			if message.message == win32.WM_QUIT {global_running = false}

			win32.TranslateMessage(&message)
			win32.DispatchMessageW(&message)
		}


		using xinput

		// TODO: not sure about polling frequency yet.
		packet_number: win32.DWORD
		for user in XUSER {
			state: XINPUT_STATE
			if result := XInputGetState(user, &state); result == .SUCCESS {
				if packet_number == state.dwPacketNumber do continue

				pad := state.Gamepad
				up := .DPAD_UP in pad.wButtons
				down := .DPAD_DOWN in pad.wButtons
				left := .DPAD_LEFT in pad.wButtons
				right := .DPAD_RIGHT in pad.wButtons
				start := .START in pad.wButtons
				back := .BACK in pad.wButtons
				left_shoulder := .LEFT_SHOULDER in pad.wButtons
				right_shoulder := .RIGHT_SHOULDER in pad.wButtons
				a_button := .A in pad.wButtons
				b_button := .B in pad.wButtons
				x_button := .X in pad.wButtons
				y_button := .Y in pad.wButtons

				stick_x := pad.sThumbLX
				stick_y := pad.sThumbLY

				// NOTE: we will do proper deadzone handling later:
                // XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE
                // XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE
				xOffset += i32(stick_x / 4096)
				yOffset -= i32(stick_y / 4096)

				sound_output.tone_hz = math.clamp(512 + 32.0 * f32(stick_y / 2000.0), 100, 1566)
                sound_output.wave_period = f32(SAMPLE_RATE)/sound_output.tone_hz
			}
		}

		// vibration: XINPUT_VIBRATION = {60000, 60000};
		// XInputSetState(0, &vibration)

		render_weird_gradient(xOffset, yOffset)

		// DirectSound output test
		play_cursor, write_cursor: u32
		if hr := secondary_buffer->getCurrentPosition(&play_cursor, &write_cursor); hr < 0 {
			_, _, code := win32.DECODE_HRESULT(hr)
			show_error_and_panic(fmt.tprintf("Error in GetCurrentPosition: code 0x%X\n", code))
		}

		bytes_to_lock: u32 = (sound_output.running_sample_index * BYTES_PER_SAMPLE) % BUFFER_SIZE
		target_cursor := (play_cursor + (sound_output.latency_sample_count * BYTES_PER_SAMPLE)) % BUFFER_SIZE
		bytes_to_write: u32

		if bytes_to_lock > target_cursor {
			bytes_to_write = BUFFER_SIZE - bytes_to_lock // we have this much ahead of us in the buffer to write to
			bytes_to_write += target_cursor // and add the first part of the buffer up to the play cursor
		} else {
			bytes_to_write = target_cursor - bytes_to_lock // we only have to fill from bytes_to_lock up to the play_cursor
		}

		win32_fill_sound_buffer(&sound_output, bytes_to_lock, bytes_to_write)

		dims := get_window_dimensions(windowHandle)

		win32_display_buffer_in_window(deviceContext, dims.width, dims.height)

		// Frame timings
		end_counter: win32.LARGE_INTEGER
        win32.QueryPerformanceCounter(&end_counter)

        counter_elapsed := end_counter - last_counter
        ms_elapsed := f32(1000 * counter_elapsed) / f32(perf_counter_frequency)
        fps := f32(perf_counter_frequency) / f32(counter_elapsed)

        //  5.5367, FPS: 180.613007, cycles: 16
        // using rdtsc
        end_cycle_count := x86._rdtsc()
        cycles_elapsed := end_cycle_count - last_cycle_count
        mcpf := cycles_elapsed / (1000 * 1000)

        win32.OutputDebugStringA(fmt.ctprintf("ms_elapsed: %.2f, FPS: %.2f, cycles: %d mc\n", ms_elapsed, fps, mcpf))

        last_counter = end_counter
        last_cycle_count = end_cycle_count

	}
}

show_error_and_panic :: proc(msg: string) {
	win32.OutputDebugStringA(strings.unsafe_string_to_cstring(msg))
	panic(msg)
}
