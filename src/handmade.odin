// Platform independent game code

package main

import "core:math"
import "core:mem"

// Compiler flags

// HANDMADE_INTERNAL indicates when we're trying to do something that we'de only want to do internally
//  (e.g., specify allocator pointer positions)
HANDMADE_INTERNAL :: #config(HANDMADE_INTERNAL, false)

// Useful "macros"
KILOBYTES :: #force_inline proc($V: uint) -> uint {return V * mem.Kilobyte}
MEGABYTES :: #force_inline proc($V: uint) -> uint {return V * mem.Megabyte}
GIGABYTES :: #force_inline proc($V: uint) -> uint {return V * mem.Gigabyte}
TERABYTES :: #force_inline proc($V: uint) -> uint {return V * mem.Terabyte}

// for now
MAX_CONTROLLER_COUNT :: 4

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
	// NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
	memory: [^]u8,
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
		pixel := transmute([^]u32)row
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

Game_Button_State :: struct {
	half_transition_count: u8,
	ended_down:            bool,
}

Game_Controller_Input :: struct {
	analog:         bool,
	start_x:        f32,
	start_y:        f32,
	min_x:          f32,
	min_y:          f32,
	max_x:          f32,
	max_y:          f32,
	end_x:          f32,
	end_y:          f32,
	a:              Game_Button_State,
	b:              Game_Button_State,
	x:              Game_Button_State,
	y:              Game_Button_State,
	left_shoulder:  Game_Button_State,
	right_shoulder: Game_Button_State,
}

Game_Input :: struct {
	// TODO: insert clock value here.
	//? seconds_elapsed: f32,
	controllers: [4]Game_Controller_Input,
}

// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: proc(
	game_memory: ^Game_Memory,
	input: ^Game_Input,
	back_buffer: ^Game_Offscreen_Buffer,
	sound_buffer: ^Game_Sound_Buffer,
) -> bool {
	when ODIN_DEBUG {
		assert(size_of(Game_State) <= len(game_memory.permanent))
	}

	state := (^Game_State)(raw_data(game_memory.permanent))
	if !state.initialized {
		state.tone_hz = 256

		bitmap_memory := DEBUG_platform_read_entire_file(#file) or_return

		DEBUG_platform_write_entire_file("data/test_file_output.txt", bitmap_memory)

		DEBUG_platform_free_file_memory(&bitmap_memory)

		state.initialized = true
	}

	input_0 := input.controllers[0]

	if input_0.analog {
		// NOTE: Use analog movement tuning
		state.tone_hz = cast(u32)math.clamp(261 + 64.0 * input_0.end_y, 120, 1566)
		state.blue_offset += i32(input_0.end_x * 4)
		state.green_offset -= i32(input_0.end_y * 4)
	} else {
		// NOTE: Use digital movement tuning
	}

	// TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
	game_sound_output(sound_buffer, state.tone_hz)

	render_weird_gradient(back_buffer, state.blue_offset, state.green_offset)

	return true
}
