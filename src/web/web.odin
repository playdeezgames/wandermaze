#+build js
package main

// Thin browser layer: the page owns requestAnimationFrame and calls these exports.
// Commands are small integers so the page does not need to know about the rules.

import "base:runtime"
import "tggd:game"

Command :: enum i32 {
	Up,
	Down,
	Left,
	Right,
	Restart,
}

state: struct {
	rules: game.Game,
	screen: game.Frame,
	dirty: bool,
}

main :: proc() {
	start(0xC0FFEE)
}

start :: proc(seed: u64) {
	game.seed_game(&state.rules, seed)
	game.init_game(&state.rules)
	state.dirty = true
}

// odin.js stops after main unless a step export exists; the page drives everything else.
@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	return true
}

// Called once by the page with entropy, before the first key.
@(export)
platform_init :: proc "c" (seed_lo, seed_hi: u32) {
	context = runtime.default_context()
	start(u64(seed_hi) << 32 | u64(seed_lo))
}

// Same rules as the cart: arrows move while alive, restart only works when dead.
@(export)
platform_command :: proc "c" (command: i32) {
	context = runtime.default_context()
	g := &state.rules
	switch Command(command) {
	case .Up:
		if g.alive { game.move_dude(g, 0, -1) }
	case .Down:
		if g.alive { game.move_dude(g, 0, 1) }
	case .Left:
		if g.alive { game.move_dude(g, -1, 0) }
	case .Right:
		if g.alive { game.move_dude(g, 1, 0) }
	case .Restart:
		if !g.alive { game.init_game(g) }
	}
	state.dirty = true
}

// Redraws if anything changed; returns 1 when the frame pointer has new pixels.
@(export)
platform_frame :: proc "c" () -> i32 {
	context = runtime.default_context()
	if !state.dirty {
		return 0
	}
	state.dirty = false
	game.draw_game(&state.screen, &state.rules)
	game.resolve(&state.screen)
	return 1
}

@(export)
platform_frame_ptr :: proc "c" () -> rawptr {
	return &state.screen.rgba
}
