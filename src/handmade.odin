package main

// Platform independent game code

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
game_offscreen_buffer :: struct {
    // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
    memory     : [^]u8,
    width      : i32,
    height     : i32,
    pitch      : i32,
}

render_weird_gradient :: proc(back_buffer: ^game_offscreen_buffer, xOffset: i32, yOffset: i32) {
	row := back_buffer.memory
	for y in 0 ..< back_buffer.height {
		pixel := transmute([^]u32)row
		for x in 0 ..< back_buffer.width {
			//                   1  2  3  4
			// pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
			//     in register: xx RR GG BB  (bc it's little endian)
			bb := u8(x + xOffset)
			gg := u8(y + yOffset)
			pixel[0] = (u32(gg) << 8) | u32(bb)
			pixel = pixel[1:]
		}

		row = row[back_buffer.pitch:]
	}
}

// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: proc(back_buffer: ^game_offscreen_buffer, xOffset: i32, yOffset: i32) {
    render_weird_gradient(back_buffer, xOffset, yOffset)
}
