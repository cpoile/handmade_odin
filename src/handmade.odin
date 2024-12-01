// Platform independent game code

package main

import "core:math"

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
	// NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
	memory: []byte,
	width:  i32,
	height: i32,
	pitch:  i32,
}

Game_Sound_Buffer :: struct {
	samples_per_second: u32,
	sample_count:       u32,
	samples:            []i16,
}

game_sound_output :: proc(sound_buffer: ^Game_Sound_Buffer, tone_hz: u32) {
	@(static) t_sine: f32
	tone_volume := 3000
	wave_period := sound_buffer.samples_per_second / tone_hz

	sample_out := sound_buffer.samples
	for i in 0 ..< sound_buffer.sample_count {
		sine_val := math.sin_f32(t_sine)
		sample_value := i16(sine_val * f32(tone_volume))
		sample_out[0] = sample_value
		sample_out = sample_out[1:]
		sample_out[0] = sample_value
		sample_out = sample_out[1:]

		t_sine += 2.0 * math.PI / f32(wave_period)
	}

}

render_weird_gradient :: proc(back_buffer: ^Game_Offscreen_Buffer, blue_offset: i32, yOffset: i32) {
	row := back_buffer.memory
	for y in 0 ..< back_buffer.height {
		pixel := transmute([^]u32)raw_data(row)
		for x in 0 ..< back_buffer.width {
			//                   1  2  3  4
			// pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
			//     in register: xx RR GG BB  (bc it's little endian)
			bb := u8(x + blue_offset)
			gg := u8(y + yOffset)
			pixel[0] = (u32(gg) << 8) | u32(bb)
			pixel = pixel[1:]
		}

		row = row[back_buffer.pitch:]
	}
}

// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: proc(
	back_buffer: ^Game_Offscreen_Buffer,
	sound_buffer: ^Game_Sound_Buffer,
	blue_offset: i32,
	green_offset: i32,
	tone_hz: u32,
) {
	// TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
	game_sound_output(sound_buffer, tone_hz)

	render_weird_gradient(back_buffer, blue_offset, green_offset)
}
