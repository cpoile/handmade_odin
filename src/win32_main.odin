package main

/* TODO: This is not the final platform layer!

  - Saved game locations
  - Getting a handle to our own executable file
  - Asset loading path
  - Threading (launch a thread)
  - Raw input (support for multiple keyboards)
  - Sleep/timeBeginPeriod
  - ClipCursor() (for muliple monitor supprot)
  - Fullscreen support
  - WM_SETCURSOR (control cursor visibility)
  - QueryCancelAutoplay
  - WM_ACTIVATEAPP (for when we are not the active application)
  - Blit speed improvements (BitBlt)
  - Hardware acceleration (OpenGL or Direct3D or BOTH??)
  - GetKeyboardLayout (for French keyboards, international WASD support)

  Just a partial list of stuff!
*/

import "../vendor/backtrace"
import "../vendor/dsound"
import "../vendor/odin-xinput/xinput"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import bits "core:math/bits"
import "core:mem"
import "core:simd/x86"
import "core:strings"
import win32 "core:sys/windows"

// aliases
L :: intrinsics.constant_utf16_cstring
int2 :: [2]i32

// consts
SAMPLE_RATE: u32 : 48000
BYTES_PER_SAMPLE :: size_of(i16) * 2
SOUND_BUFFER_SIZE :: SAMPLE_RATE * BYTES_PER_SAMPLE
// TODO: how do we reliably query this on Windows?
MONITOR_REFRESH_HZ :: 60
GAME_UPDATE_HZ :: 30
TARGET_MS_PER_GAME_UPDATE :: 1000 / cast(f32)GAME_UPDATE_HZ
TARGET_SECONDS_PER_FRAME :: cast(f32)1 / cast(f32)GAME_UPDATE_HZ

Game_Memory :: struct {
	permanent: []u8, // NOTE: REQUIRED to be initialized to zero at startup. Windows does, make sure other platforms do.
	temporary: []u8,
}

Game_State :: struct {
	initialized:  bool,
	blue_offset:  i32,
	green_offset: i32,
	tone_hz:      u32,
}

offscreen_buffer :: struct {
	BitmapInfo:      win32.BITMAPINFO,
	memory:          []u8,
	width:           u32,
	height:          u32,
	pitch:           u32,
	bytes_per_pixel: u32,
}

win32_window_dimensions :: struct {
	width:  i32,
	height: i32,
}

win32_sound_output :: struct {
	running_sample_index: u32,
	wave_period:          u32,
	safety_bytes:         u32,
}

global_running := true
GlobalBackBuffer: offscreen_buffer
secondary_sound_buffer: ^dsound.Buffer
global_perf_counter_frequency: win32.LARGE_INTEGER

// Services that the platform layer provides the game
//
// should be using a when here, but it ruins ols, so no can do (until ols is when-aware)
//when HANDMADE_INTERNAL {
//
// NOTE: These are not for anything in the shipping game.
//  They are blocking and the write doesn't protect against lost data!
DEBUG_platform_read_entire_file :: proc(filename: string) -> (memory: []u8, ok: bool) {
	fh := win32.CreateFileW(
		win32.utf8_to_wstring(filename),
		win32.GENERIC_READ,
		win32.FILE_SHARE_READ,
		nil,
		win32.OPEN_EXISTING,
		0,
		nil,
	)

	if fh == nil {return}

	size: win32.LARGE_INTEGER
	win32.GetFileSizeEx(fh, &size) or_return

	assert(size < bits.U32_MAX)

	raw_mem := win32.VirtualAlloc(nil, uint(size), win32.MEM_RESERVE | win32.MEM_COMMIT, win32.PAGE_READWRITE)

	if raw_mem == nil {return nil, false}

	memory = mem.byte_slice(raw_mem, size)

	defer if !ok {
		DEBUG_platform_free_file_memory(&memory)
	}

	bytes_read: win32.DWORD
	win32.ReadFile(fh, raw_mem, cast(u32)size, &bytes_read, nil) or_return

	if bytes_read != cast(u32)size {return}

	win32.CloseHandle(fh) or_return

	return memory, true
}

DEBUG_platform_free_file_memory :: proc(memory: ^[]u8) {
	raw := transmute(mem.Raw_Slice)memory^
	win32.VirtualFree(raw.data, 0, win32.MEM_RELEASE)
	raw.len = 0
	memory^ = transmute([]u8)raw
}
DEBUG_platform_write_entire_file :: proc(filename: string, memory: []u8) -> (ok: bool) {
	fh := win32.CreateFileW(win32.utf8_to_wstring(filename), win32.GENERIC_WRITE, 0, nil, win32.CREATE_ALWAYS, 0, nil)

	if fh == nil {return}

	bytes_written: win32.DWORD
	win32.WriteFile(fh, raw_data(memory), cast(u32)len(memory), &bytes_written, nil) or_return

	return bytes_written == cast(u32)len(memory)
}
//}


win32_fill_sound_buffer :: proc(
	sound_output: ^win32_sound_output,
	source_buffer: ^Game_Sound_Buffer,
	byte_to_lock, bytes_to_write: u32,
) {
	//  u16   u16     u16   u16    u16   u16
	// [left right] [left right] [left right]
	region1, region2: rawptr
	size1, size2: u32
	if win32.SUCCEEDED(secondary_sound_buffer->lock(byte_to_lock, bytes_to_write, &region1, &size1, &region2, &size2, 0)) {
		region1_sample_count := size1 / BYTES_PER_SAMPLE
		dest_samples := cast([^]i16)region1
		src_samples := source_buffer.samples
		for _ in 0 ..< region1_sample_count {
			dest_samples[0] = src_samples[0]
			dest_samples = dest_samples[1:]
			src_samples = src_samples[1:]

			dest_samples[0] = src_samples[0]
			dest_samples = dest_samples[1:]
			src_samples = src_samples[1:]
			sound_output.running_sample_index += 1
		}

		dest_samples = cast([^]i16)region2
		region2_sample_count := size2 / BYTES_PER_SAMPLE
		for _ in 0 ..< region2_sample_count {
			dest_samples[0] = src_samples[0]
			dest_samples = dest_samples[1:]
			src_samples = src_samples[1:]

			dest_samples[0] = src_samples[0]
			dest_samples = dest_samples[1:]
			src_samples = src_samples[1:]
			sound_output.running_sample_index += 1
		}
		secondary_sound_buffer->unlock(region1, size1, region2, size2)
	}
}

get_window_dimensions :: proc(window: win32.HWND) -> win32_window_dimensions {
	client_rect: win32.RECT
	win32.GetClientRect(window, &client_rect)
	return {client_rect.right - client_rect.left, client_rect.bottom - client_rect.top}
}

win32_resize_DIB_section :: proc(back_buffer: ^offscreen_buffer, width: u32, height: u32) {
	if (back_buffer.memory != nil) {delete(back_buffer.memory)}
	back_buffer.width = width
	back_buffer.height = height
	back_buffer.bytes_per_pixel = 4
	back_buffer.pitch = width * back_buffer.bytes_per_pixel

	// NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
	// bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
	// not the bottom left
	back_buffer.BitmapInfo.bmiHeader.biSize = size_of(type_of(back_buffer.BitmapInfo.bmiHeader))
	back_buffer.BitmapInfo.bmiHeader.biWidth = i32(width)
	back_buffer.BitmapInfo.bmiHeader.biHeight = i32(-height)
	back_buffer.BitmapInfo.bmiHeader.biPlanes = 1
	back_buffer.BitmapInfo.bmiHeader.biBitCount = 32
	back_buffer.BitmapInfo.bmiHeader.biCompression = win32.BI_RGB

	bitmap_memory_size := uint((back_buffer.width * back_buffer.height) * back_buffer.bytes_per_pixel)
	back_buffer.memory = make([]byte, bitmap_memory_size)
}

win32_display_buffer_in_window :: proc(
	back_buffer: ^offscreen_buffer,
	deviceContext: win32.HDC,
	destWidth: i32,
	destHeight: i32,
) {
	// TODO: aspect ratio correction
	win32.StretchDIBits(
		deviceContext,
		0,
		0,
		destWidth,
		destHeight,
		0,
		0,
		i32(back_buffer.width),
		i32(back_buffer.height),
		raw_data(back_buffer.memory),
		&back_buffer.BitmapInfo,
		win32.DIB_RGB_COLORS,
		win32.SRCCOPY,
	)
}

win32_debug_draw_vertical :: proc(back_buffer: ^offscreen_buffer, x: u32, top: u32, bottom: u32, color: u32) {
	pixel := back_buffer.memory[x * back_buffer.bytes_per_pixel + top * back_buffer.pitch:]
	for y in top ..< bottom {
		(cast([^]u32)raw_data(pixel))[0] = color
		pixel = pixel[back_buffer.pitch:]
	}
}

win32_debug_sync_display :: proc(
	back_buffer: ^offscreen_buffer,
	last_play_cursor_count: int,
	last_play_cursors: []u32,
	sound_output: ^win32_sound_output,
) {
	// TODO: draw where we're writing out sound -- doesn't match casey's code in this proc

	pad_x: u32 = 16
	pad_y: u32 = 16
	top := pad_y
	bottom: u32 = back_buffer.height - 16

	// remember Casey's talk on dimentional analysis: to change something mapped in sound buffer size into back_buffer size,
	// mult by coefficient C. The sound buffer sized thing cancels out with the denominator, leaving back_buffer units.
	C := cast(f32)(back_buffer.width - 2 * pad_x) / cast(f32)SOUND_BUFFER_SIZE
	for i in 0 ..< len(last_play_cursors) {
		last_play_cursor := last_play_cursors[i]
		x := pad_x + cast(u32)(C * cast(f32)last_play_cursor)
		win32_debug_draw_vertical(back_buffer, x, top, bottom, 0xFFFFFFFF)
	}
}


win32_main_window_callback :: proc "system" (
	window: win32.HWND,
	message: u32,
	WParam: win32.WPARAM,
	LParam: win32.LPARAM,
) -> win32.LRESULT {
	using win32
	context = runtime.default_context()

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
		assert(false, "Keyboard input came in througha  non-dispatch message!")

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
		win32_display_buffer_in_window(&GlobalBackBuffer, device_context, dims.width, dims.height)

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

create_window :: #force_inline proc(instance: win32.HINSTANCE, atom: win32.ATOM, size: int2) -> win32.HWND {
	size := size
	if atom == 0 {show_error_and_panic("atom is zero")}
	style :: win32.WS_OVERLAPPEDWINDOW
	pos := int2{i32(win32.CW_USEDEFAULT), i32(win32.CW_USEDEFAULT)}
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

win32_process_xinput_digital_button :: proc(
	old_state: Game_Button_State,
	new_state: ^Game_Button_State,
	button_bit: xinput.XINPUT_GAMEPAD_BUTTON_BIT,
	button_state: xinput.XINPUT_GAMEPAD_BUTTON,
) {
	new_state.ended_down = button_bit in button_state
	new_state.half_transition_count = old_state.ended_down != new_state.ended_down
}

win32_process_keyboard_message :: proc(new_state: ^Game_Button_State, isDown: bool) {
	assert(new_state.ended_down != isDown) // should only get this when isDown changes
	new_state.ended_down = isDown
	new_state.half_transition_count += 1
}

win32_process_messages :: proc(keyboard_controller: ^Game_Controller_Input) {
	using win32

	message: MSG
	for PeekMessageA(&message, nil, 0, 0, PM_REMOVE) {
		switch message.message {
		case WM_QUIT:
			global_running = false
		case WM_SYSKEYDOWN, WM_SYSKEYUP, WM_KEYDOWN, WM_KEYUP:
			vk_code := message.wParam
			lParam := message.lParam
			altDown := (lParam & (1 << 29)) != 0
			wasDown := (lParam & (1 << 30)) != 0
			isDown := (lParam & (1 << 31)) == 0
			if (isDown != wasDown) {
				switch vk_code {
				case VK_F4:
					if altDown {global_running = false}
				case 'W':
					win32_process_keyboard_message(&keyboard_controller.move_up, isDown)
				case 'R':
					win32_process_keyboard_message(&keyboard_controller.move_down, isDown)
				case 'A':
					win32_process_keyboard_message(&keyboard_controller.move_left, isDown)
				case 'S':
					win32_process_keyboard_message(&keyboard_controller.move_right, isDown)
				case VK_UP:
					win32_process_keyboard_message(&keyboard_controller.action_up, isDown)
				case VK_DOWN:
					win32_process_keyboard_message(&keyboard_controller.action_down, isDown)
				case VK_LEFT:
					win32_process_keyboard_message(&keyboard_controller.action_left, isDown)
				case VK_RIGHT:
					win32_process_keyboard_message(&keyboard_controller.action_right, isDown)
				case 'Q':
					win32_process_keyboard_message(&keyboard_controller.left_shoulder, isDown)
				case 'F':
					win32_process_keyboard_message(&keyboard_controller.right_shoulder, isDown)
				case VK_ESCAPE:
					global_running = false
				}
			}
		case:
			TranslateMessage(&message)
			DispatchMessageW(&message)
		}
	}
}

win32_get_wall_clock :: #force_inline proc() -> win32.LARGE_INTEGER {
	res: win32.LARGE_INTEGER
	win32.QueryPerformanceCounter(&res)
	return res
}

win32_get_seconds_elapsed :: #force_inline proc(start: win32.LARGE_INTEGER, end: win32.LARGE_INTEGER) -> f32 {
	return cast(f32)(end - start) / cast(f32)global_perf_counter_frequency
}

main :: proc() {
	using win32

	backtrace.register_segfault_handler()

	QueryPerformanceFrequency(&global_perf_counter_frequency)

	// NOTE: Set the windows scheduler granularity, so our sleep can be better
	desired_scheduler_ms :: 1
	sleep_is_granular := timeBeginPeriod(desired_scheduler_ms) == TIMERR_NOERROR
	defer timeEndPeriod(desired_scheduler_ms)

	instance := HINSTANCE(GetModuleHandleW(nil))
	if (instance == nil) {show_error_and_panic("No instance")}
	atom := register_class(instance)
	if atom == 0 {show_error_and_panic("Failed to register window class")}
	//defer unregister_class(atom, instance)  // TODO: crashing, not sure why.

	size := int2{1280, 720}
	windowHandle := create_window(instance, atom, size)
	if windowHandle == nil {show_error_and_panic("Failed to create window")}
	ShowWindow(windowHandle, SW_SHOWDEFAULT)
	UpdateWindow(windowHandle)

	win32_resize_DIB_section(&GlobalBackBuffer, cast(u32)size.x, cast(u32)size.y)
	defer delete(GlobalBackBuffer.memory)

	// NOTE: since we specified CS_OWNDC, we can just get one device context and use it
	// forever because we are not sharing it with anyone.
	deviceContext := GetDC(windowHandle)

	// TODO: compute to see how low we can go
	sound_output := win32_sound_output {
		safety_bytes = ((SAMPLE_RATE * BYTES_PER_SAMPLE) / GAME_UPDATE_HZ) / 3,
	}

	dsound.load(windowHandle, &secondary_sound_buffer, SOUND_BUFFER_SIZE, SAMPLE_RATE)
	// no need to clear the secondary_sound_buffer in Odin, it's initialized to zero.
	if hr := secondary_sound_buffer->play(0, 0, dsound.DSBPLAY_LOOPING); hr < 0 {
		_, _, code := DECODE_HRESULT(hr)
		show_error_and_panic(fmt.tprintf("Error in Play: code 0x%X\n", code))
	}

	// TODO: pool with bitmap make -- needed for odin? maybe not...
	samples := make([]i16, SOUND_BUFFER_SIZE / 2) // BUFFER_SIZE is in bytes, therefore
	defer delete(samples)

	// NOTE: Casey uses VirtualAlloc, so I'm going to do the same (for now). We're simulating our own allocator, so why not go raw.

	when HANDMADE_INTERNAL {
		base_address: LPVOID = transmute(rawptr)TERABYTES(2) // in windows 64-bit, first 8 terabytes are reserved for the application
	} else {
		base_address: LPVOID = nil
	}
	game_memory := Game_Memory{}
	permanent_len := MEGABYTES(64)
	temporary_len := GIGABYTES(4)

	// TODO: Handle various memory footprints.
	raw_mem := VirtualAlloc(base_address, permanent_len + temporary_len, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE)
	if raw_mem == nil {
		show_error_and_panic(fmt.tprint("Could not allocate memory for game, exiting!"))
	}
	game_memory.permanent = mem.byte_slice(raw_mem, permanent_len)
	game_memory.temporary = mem.byte_slice(cast(rawptr)(uintptr(raw_mem) + uintptr(permanent_len)), temporary_len)

	// Frame timings
	last_counter := win32_get_wall_clock()
	last_cycle_count := x86._rdtsc()

	debug_last_play_cursor_index := 0
	debug_last_play_cursor: [GAME_UPDATE_HZ / 2]u32 = 0

	audio_latency_bytes: u32
	audio_latency_sec: f32
	sound_is_valid := false

	new_input := &Game_Input{}
	old_input := &Game_Input{}

	for (global_running) {
		using xinput

		// zero the keyboard at the start of each frame
		old_keyboard_controller := &old_input.controllers[0]
		new_keyboard_controller := &new_input.controllers[0]
		new_keyboard_controller^ = {
			isConnected = true,
		}
		for i in 0 ..< 10 {
			new_keyboard_controller.buttons[i].ended_down = old_keyboard_controller.buttons[i].ended_down
		}

		win32_process_messages(new_keyboard_controller)

		// TODO: Need to not poll disconnected controllers to avoid xinput frame rate hit on older libraries
		// TODO: not sure about polling frequency yet.
		packet_number: DWORD
		for user, i in XUSER {
			if i >= MAX_CONTROLLER_COUNT {
				// skip unsupported controllers, for simplicity
				continue
			}

			controller_idx := i + 1
			old_controller := &old_input.controllers[controller_idx]
			new_controller := &new_input.controllers[controller_idx]

			state: XINPUT_STATE
			if result := XInputGetState(user, &state); result == .SUCCESS {
				if packet_number == state.dwPacketNumber do continue
				new_controller.isConnected = true
				pad := state.Gamepad

				// TODO: this is a square deadzone, check XINPUT to verify if the deadzone is round
				dzone := XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE
				x := (pad.sThumbLX < dzone) ? cast(f32)pad.sThumbLX / 32768 : cast(f32)pad.sThumbLX / 32767
				y := (pad.sThumbLY < -dzone) ? cast(f32)pad.sThumbLY / 32768 : cast(f32)pad.sThumbLY / 32767

				new_controller.analog = true
				new_controller.stick_avg_x = x
				new_controller.stick_avg_y = y
				if .DPAD_UP in pad.wButtons {new_controller.stick_avg_y = 1}
				if .DPAD_DOWN in pad.wButtons {new_controller.stick_avg_y = -1}
				if .DPAD_LEFT in pad.wButtons {new_controller.stick_avg_x = -1}
				if .DPAD_RIGHT in pad.wButtons {new_controller.stick_avg_x = 1}

				// NOTE: not doing the stick->move_up/down/etc mapping that Casey did. Maybe I'll do it if we need it later.

				win32_process_xinput_digital_button(
					old_controller.move_up,
					&new_controller.move_up,
					.DPAD_UP,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(
					old_controller.move_down,
					&new_controller.move_down,
					.DPAD_DOWN,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(
					old_controller.move_left,
					&new_controller.move_left,
					.DPAD_LEFT,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(
					old_controller.move_right,
					&new_controller.move_right,
					.DPAD_RIGHT,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(old_controller.a, &new_controller.a, .A, pad.wButtons)
				win32_process_xinput_digital_button(old_controller.b, &new_controller.b, .B, pad.wButtons)
				win32_process_xinput_digital_button(old_controller.x, &new_controller.x, .X, pad.wButtons)
				win32_process_xinput_digital_button(old_controller.y, &new_controller.y, .Y, pad.wButtons)
				win32_process_xinput_digital_button(
					old_controller.left_shoulder,
					&new_controller.left_shoulder,
					.LEFT_SHOULDER,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(
					old_controller.right_shoulder,
					&new_controller.right_shoulder,
					.RIGHT_SHOULDER,
					pad.wButtons,
				)
				win32_process_xinput_digital_button(old_controller.back, &new_controller.back, .BACK, pad.wButtons)
				win32_process_xinput_digital_button(old_controller.start, &new_controller.start, .START, pad.wButtons)
			} else {
				new_controller.isConnected = false
			}
		}

		/* NOTE: How sound output computation works

		   We define a safety value that is the number of samples we think our game update loop may vary by (let's say up to 2ms).
		   When we wake up to write audio, we will look atnd see what the play cursor position is and we will forecast
		   ahead where we think the play cursor will be on the next frame boundary.

		   We will then look to see if the write cursor is before that. If it is, the target fill position is that frame
		   boundary plus one frame. we will write up to the next frame boundary from the write cursor, and then one frame.
		   This gives us perfect audio sync in the case of a card that has low enough latency.

		   If the write cursor is _after_ that safety margin, then we assume we can never sync the audio perfectly,
		   so we will write one frame's worth of audio plus plus the safety margin's worth of guard samples.
		*/

		buffer := Game_Offscreen_Buffer {
			memory = raw_data(GlobalBackBuffer.memory),
			width  = GlobalBackBuffer.width,
			height = GlobalBackBuffer.height,
			pitch  = GlobalBackBuffer.pitch,
		}
		if !game_update_and_render(&game_memory, new_input, &buffer) {
			show_error_and_panic(
				"game_update_and_render returned false, exiting. We'll work out proper error handling soon I hope.\n",
			)
		}

		play_cursor, write_cursor: u32
		// write cursor is where it's safe to write, play_cursor is where we are right now,
		// so write_cursor - play_cursor (+ wraparound) is our minimum latency
		if hr := secondary_sound_buffer->getCurrentPosition(&play_cursor, &write_cursor); hr > 0 {
			_, _, code := DECODE_HRESULT(hr)
			show_error(fmt.tprintf("Error in GetCurrentPosition: code 0x%X\n", code))
			sound_is_valid = false
		} else {
			byte_to_lock, target_cursor, bytes_to_write: u32

			if !sound_is_valid {
				// we must be starting, or we failed getting position sometime earlier
				sound_output.running_sample_index = write_cursor / BYTES_PER_SAMPLE
				sound_is_valid = true
			}

			expected_sound_bytes_per_frame := (SAMPLE_RATE * BYTES_PER_SAMPLE) / GAME_UPDATE_HZ
			expected_frame_boundary_byte := play_cursor + expected_sound_bytes_per_frame
			safe_write_cursor := write_cursor
			if safe_write_cursor < play_cursor {
				safe_write_cursor += SOUND_BUFFER_SIZE
			}
			assert(safe_write_cursor >= play_cursor)

			safe_write_cursor += sound_output.safety_bytes
			audio_card_is_low_latency := safe_write_cursor < expected_frame_boundary_byte

			byte_to_lock = (sound_output.running_sample_index * BYTES_PER_SAMPLE) % SOUND_BUFFER_SIZE
			if audio_card_is_low_latency {
				target_cursor = write_cursor + expected_frame_boundary_byte + expected_sound_bytes_per_frame
			} else {
				target_cursor = write_cursor + expected_sound_bytes_per_frame + sound_output.safety_bytes
			}
			target_cursor %= SOUND_BUFFER_SIZE

			if byte_to_lock > target_cursor {
				bytes_to_write = SOUND_BUFFER_SIZE - byte_to_lock // we have this much ahead of us in the buffer to write to
				bytes_to_write += target_cursor // and add the first part of the buffer up to the play cursor
			} else {
				bytes_to_write = target_cursor - byte_to_lock // we only have to fill from bytes_to_lock up to the play_cursor
			}

			game_sound_buffer := Game_Sound_Buffer {
				samples_per_second = SAMPLE_RATE,
				sample_count       = bytes_to_write / BYTES_PER_SAMPLE,
				samples            = samples,
			}
			game_get_sound_samples(&game_memory, &game_sound_buffer)
			win32_fill_sound_buffer(&sound_output, &game_sound_buffer, byte_to_lock, bytes_to_write)

			//secondary_sound_buffer->getCurrentPosition(&play_cursor, &write_cursor)

			wrapped_around := play_cursor > write_cursor
			audio_latency_bytes =
				(wrapped_around) ? write_cursor + SOUND_BUFFER_SIZE - play_cursor : write_cursor - play_cursor
			audio_latency_sec = (cast(f32)audio_latency_bytes / cast(f32)BYTES_PER_SAMPLE / cast(f32)SAMPLE_RATE)

			OutputDebugStringA(
				fmt.ctprintf(
					"BTL:  %d -  PC: %d  WC: %d  TC: %d  DELTA: %d  LATENCY_SEC: %.2f  Low Latency? %t\n",
					byte_to_lock,
					play_cursor,
					write_cursor,
					target_cursor,
					audio_latency_bytes,
					audio_latency_sec,
					audio_card_is_low_latency,
				),
			)
		}

		// Frame timings
		// TODO: not tested yet, probably buggy!!!
		work_counter := win32_get_wall_clock()
		work_sec_elapsed := win32_get_seconds_elapsed(last_counter, work_counter)

		sec_elapsed_for_frame := work_sec_elapsed
		if sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME {
			if sleep_is_granular {
				// -1 b/c it was oversleeping on my machine (different than casey's, not sure why. But this gives us a solid 33.33 ms/frame)
				sleep_ms := cast(u32)(1000 * (TARGET_SECONDS_PER_FRAME - sec_elapsed_for_frame)) - 1
				if sleep_ms > 0 do win32.Sleep(sleep_ms)
			}

			//test_sec_elapsed_for_frame := win32_get_seconds_elapsed(last_counter, win32_get_wall_clock())
			//assert(test_sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME)

			sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock())
			for sec_elapsed_for_frame < TARGET_SECONDS_PER_FRAME {
				sec_elapsed_for_frame = win32_get_seconds_elapsed(last_counter, win32_get_wall_clock())
			}
		} else {
			fmt.printf("missed a frame! sec_elapsed_for_frame > target_seconds_per_frame")
		}

		end_counter := win32_get_wall_clock()
		ms_per_frame := cast(f32)1000 * win32_get_seconds_elapsed(last_counter, end_counter)
		last_counter = end_counter

		// Display the frame
		dims := get_window_dimensions(windowHandle)

		when HANDMADE_INTERNAL {
			win32_debug_sync_display(
				&GlobalBackBuffer,
				debug_last_play_cursor_index,
				debug_last_play_cursor[:],
				&sound_output,
			)
		}
		// buffer FLIP
		win32_display_buffer_in_window(&GlobalBackBuffer, deviceContext, dims.width, dims.height)


		when HANDMADE_INTERNAL {
			// NOTE: this is debug code
			// We want the play cursor that we sampled back when we flipped the previous frame, and we want to add our frame latency into that.

			//play_cursor2, write_cursor2: u32
			// write cursor is where it's safe to write, play_cursor2 is where we are right now,
			// so write_cursor2 - play_cursor2 (+ wraparound) is our minimum latency
			// if hr := secondary_sound_buffer->getCurrentPosition(&play_cursor2, &write_cursor2); hr > 0 {
			// 	_, _, code := DECODE_HRESULT(hr)
			// 	show_error(fmt.tprintf("Error in GetCurrentPosition: code 0x%X\n", code))
			// } else {
			// }
			debug_last_play_cursor[debug_last_play_cursor_index] = play_cursor
			debug_last_play_cursor_index += 1
			debug_last_play_cursor_index %= len(debug_last_play_cursor)
		}

		// using rdtsc
		end_cycle_count := x86._rdtsc()
		cycles_elapsed := end_cycle_count - last_cycle_count
		mcpf := cycles_elapsed / (1000 * 1000)
		fps := 0.0

		OutputDebugStringA(fmt.ctprintf("ms_per_frame: %.2f, FPS: %.2f, cycles: %d mc\n", ms_per_frame, fps, mcpf))

		last_cycle_count = end_cycle_count

		new_input, old_input = old_input, new_input
	}
}

show_error_and_panic :: proc(msg: string) {
	win32.OutputDebugStringA(strings.unsafe_string_to_cstring(msg))
	panic(msg)
}

show_error :: proc(msg: string) {
	win32.OutputDebugStringA(strings.unsafe_string_to_cstring(msg))
}
