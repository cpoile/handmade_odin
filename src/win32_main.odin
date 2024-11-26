package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"
import win32 "core:sys/windows"
import "../vendor/odin-xinput/xinput"

// aliases
L :: intrinsics.constant_utf16_cstring
int2 :: [2]i32

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

global_running := true
GlobalBackBuffer: offscreen_buffer

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
	if (GlobalBackBuffer.memory !=
		   nil) {win32.VirtualFree(GlobalBackBuffer.memory, 0, win32.MEM_RELEASE)}
	GlobalBackBuffer.width = width
	GlobalBackBuffer.height = height
	bytes_per_pixel :: 4
	GlobalBackBuffer.pitch = width * bytes_per_pixel

	// NOTE: When the biHeight field is negative, this is the clue to Windows to treat this bitmap as top down, not
	// bottom up, meaning that the first 3 bytes of the image are the color for the top left pixel in the bitmap,
	// not the bottom left
	GlobalBackBuffer.BitmapInfo.bmiHeader.biSize = size_of(
		type_of(GlobalBackBuffer.BitmapInfo.bmiHeader),
	)
	GlobalBackBuffer.BitmapInfo.bmiHeader.biWidth = width
	GlobalBackBuffer.BitmapInfo.bmiHeader.biHeight = -height
	GlobalBackBuffer.BitmapInfo.bmiHeader.biPlanes = 1
	GlobalBackBuffer.BitmapInfo.bmiHeader.biBitCount = 32
	GlobalBackBuffer.BitmapInfo.bmiHeader.biCompression = win32.BI_RGB

	bitmap_memory_size := uint(
		(GlobalBackBuffer.width * GlobalBackBuffer.height) * bytes_per_pixel,
	)
	GlobalBackBuffer.memory =
	transmute([^]u8)win32.VirtualAlloc(
		nil,
		bitmap_memory_size,
		win32.MEM_COMMIT,
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

	alt_is_down := false;

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
        wasDown := (LParam & (1 << 30)) != 0
        isDown := (LParam & (1 << 31)) == 0
        if (isDown != wasDown) {
            // NOTE: not real code, just a placeholder, later we'll use a switch or something.
            if      vk_code == VK_MENU    {alt_is_down = isDown}
            else if vk_code == VK_F4      {global_running = false}
            else if vk_code == 'W'        {OutputDebugStringA("W\n")}
            else if vk_code == 'A'        {OutputDebugStringA("A\n")}
            else if vk_code == 'R'        {OutputDebugStringA("R\n")}
            else if vk_code == 'S'        {OutputDebugStringA("S\n")}
            else if vk_code == 'Q'        {OutputDebugStringA("Q\n")}
            else if vk_code == 'F'        {OutputDebugStringA("F\n")}
            else if vk_code == VK_UP      {OutputDebugStringA("up\n")}
            else if vk_code == VK_DOWN    {OutputDebugStringA("down\n")}
            else if vk_code == VK_LEFT    {OutputDebugStringA("left\n")}
            else if vk_code == VK_RIGHT   {OutputDebugStringA("Right\n")}
            else if vk_code == VK_ESCAPE  {OutputDebugStringA(strings.unsafe_string_to_cstring(fmt.tprintf("Escape is down? %t was down? %t\n", isDown, wasDown)))}
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
	if !win32.UnregisterClassW(
		win32.LPCWSTR(uintptr(atom)),
		instance,
	) {show_error_and_panic("UnregisterClassW")}
}

adjust_size_for_style :: proc(size: ^int2, dwStyle: win32.DWORD) {
	rect := win32.RECT{0, 0, size.x, size.y}
	if win32.AdjustWindowRect(&rect, dwStyle, false) {
		size^ = {i32(rect.right - rect.left), i32(rect.bottom - rect.top)}
	}
}

create_window :: #force_inline proc(
	instance: win32.HINSTANCE,
	atom: win32.ATOM,
	game: ^Game,
) -> win32.HWND {
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

	// NOTE: since we specified CS_OWNDC (in Window_Creation/windows.jai), we can just get one device context and use it
	// forever because we are not sharing it with anyone.
	deviceContext := win32.GetDC(windowHandle)

	xOffset: i32 = 0
	yOffset: i32 = 0

	message: win32.MSG
	for (global_running) {
		if win32.PeekMessageA(&message, nil, 0, 0, win32.PM_REMOVE) {
			if message.message == win32.WM_QUIT {global_running = false}

			win32.TranslateMessage(&message)
			win32.DispatchMessageW(&message)
		}

		// TODO: not sure about polling frequency yet.
		using xinput

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

				xOffset += i32(stick_x >> 12)
                yOffset -= i32(stick_y >> 12)
            }
        }

        // vibration: XINPUT_VIBRATION = {60000, 60000};
		// XInputSetState(0, &vibration)

		render_weird_gradient(xOffset, yOffset)

		dims := get_window_dimensions(windowHandle)

		win32_display_buffer_in_window(deviceContext, dims.width, dims.height)
	}
}

show_error_and_panic :: proc(msg: string) {
	win32.OutputDebugStringA(strings.unsafe_string_to_cstring(msg))
	panic(msg)
}
