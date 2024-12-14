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
MAX_INPUTS :: MAX_CONTROLLER_COUNT + 1 // for keyboard

// TODO: In the future, rendering _specifically_ will become a three-tiered abstraction!!
Game_Offscreen_Buffer :: struct {
	// NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX
	memory: [^]u8,
	width:  u32,
	height: u32,
	pitch:  u32,
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
	for _ in 0 ..< sound_buffer.sample_count {
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
		pixel := cast([^]u32)row
		for x in 0 ..< back_buffer.width {
			//                   1  2  3  4
			// pixel in memory: BB GG RR xx  (bc MSFT wanted to see RGB in register (see register)
			//     in register: xx RR GG BB  (bc it's little endian)
			bb := u8(i32(x) + blue_offset)
			gg := u8(i32(y) + yOffset)
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
	isConnected: bool,
	analog:      bool,
	stick_avg_x: f32,
	stick_avg_y: f32,
	using _:     struct #raw_union {
		buttons: [16]Game_Button_State,
		using _: struct {
			move_up:        Game_Button_State,
			move_down:      Game_Button_State,
			move_left:      Game_Button_State,
			move_right:     Game_Button_State,
			action_up:      Game_Button_State,
			action_down:    Game_Button_State,
			action_left:    Game_Button_State,
			action_right:   Game_Button_State,
			left_shoulder:  Game_Button_State,
			right_shoulder: Game_Button_State,
			a:              Game_Button_State,
			b:              Game_Button_State,
			x:              Game_Button_State,
			y:              Game_Button_State,
			back:           Game_Button_State,
			start:          Game_Button_State,
			// NOTE: always add new buttons above the terminator.
			terminator:     Game_Button_State,
		},
	},
}

Game_Input :: struct {
	// TODO: insert clock value here.
	//? seconds_elapsed: f32,
	controllers: [MAX_INPUTS]Game_Controller_Input,
}

// NOTE: at the moment this has to be a very fast function, it cannot be more than a ms or so.
game_get_sound_samples :: proc(game_memory: ^Game_Memory, sound_buffer: ^Game_Sound_Buffer) {
	// TODO: Allow sample offsets here (eg, set sound further out in the future, or closer to immediately)
	state := (^Game_State)(raw_data(game_memory.permanent))

	game_sound_output(sound_buffer, state.tone_hz)
}

// NOTE: may expand in the future
// need FOUR THINGS: timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
game_update_and_render :: proc(
	game_memory: ^Game_Memory,
	input: ^Game_Input,
	back_buffer: ^Game_Offscreen_Buffer,
) -> bool {
	when ODIN_DEBUG {
		assert(size_of(Game_State) <= len(game_memory.permanent))
		assert(
			(cast(uintptr)&input.controllers[0].terminator - cast(uintptr)&input.controllers[0].move_up) ==
			len(input.controllers[0].buttons) * size_of(Game_Button_State),
		)
	}

	state := (^Game_State)(raw_data(game_memory.permanent))
	if !state.initialized {
		state.tone_hz = 256

		bitmap_memory := DEBUG_platform_read_entire_file(#file) or_return

		DEBUG_platform_write_entire_file("data/test_file_output.txt", bitmap_memory)

		DEBUG_platform_free_file_memory(&bitmap_memory)

		state.initialized = true
	}

	for i in 0 ..< MAX_INPUTS {
		input := input.controllers[i]

		if input.analog {
			// NOTE: Use analog movement tuning
			state.tone_hz = cast(u32)math.clamp(261 + 64.0 * input.stick_avg_y, 120, 1566)
			state.blue_offset += cast(i32)(input.stick_avg_x * 10)
			state.green_offset -= cast(i32)(input.stick_avg_y * 10)
		}

		state.blue_offset += (input.move_right.ended_down ? 1 : 0) * 10
		state.blue_offset -= (input.move_left.ended_down ? 1 : 0) * 10
		state.green_offset -= (input.move_up.ended_down ? 1 : 0) * 10
		state.green_offset += (input.move_down.ended_down ? 1 : 0) * 10
	}

	render_weird_gradient(back_buffer, state.blue_offset, state.green_offset)

	return true
}
