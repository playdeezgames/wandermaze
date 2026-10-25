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
	flames: game.Animation,
	dirty: bool,
}

main :: proc() {
	start(0xC0FFEE)
}

start :: proc(seed: u64) {
	game.seed_game(&state.rules, seed)
	game.init_game(&state.rules)
	state.rules.phase = .Title // the board is dealt behind the title screen
	game.init_animation(&state.flames, seed ~ 0xF1A3E5)
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

// Arrows move while playing; any command leaves the title screen (without moving); restart
// works from the game over screen once its short delay has passed.
@(export)
platform_command :: proc "c" (command: i32) {
	context = runtime.default_context()
	g := &state.rules
	switch g.phase {
	case .Title:
		game.begin(g)
	case .Playing:
		switch Command(command) {
		case .Up:
			game.move_dude(g, 0, -1)
		case .Down:
			game.move_dude(g, 0, 1)
		case .Left:
			game.move_dude(g, -1, 0)
		case .Right:
			game.move_dude(g, 1, 0)
		case .Restart:
		}
	case .Level_Complete:
		game.proceed(g) // any key once the screen has waited a moment
	case .Game_Over:
		if Command(command) == .Restart {
			game.restart(g)
		}
	}
	state.dirty = true
}

// The sound of the last move (game.Sound as an integer, 0 for none); reading it clears it.
@(export)
platform_take_sound :: proc "c" () -> i32 {
	sound := state.rules.sound
	state.rules.sound = .None
	return i32(sound)
}

// Called once per animation frame with the seconds since the last one. Redraws when a move
// happened or a flame flickered; returns 1 when the frame pointer has new pixels.
@(export)
platform_frame :: proc "c" (dt: f32) -> i32 {
	context = runtime.default_context()
	flickered := game.step_animation(&state.flames, &state.rules, dt)
	ready := game.tick(&state.rules, dt) // the game over prompt appears after its delay
	if !state.dirty && !flickered && !ready {
		return 0
	}
	state.dirty = false
	game.draw_game(&state.screen, &state.rules, &state.flames)
	game.resolve(&state.screen)
	return 1
}

@(export)
platform_frame_ptr :: proc "c" () -> rawptr {
	return &state.screen.rgba
}

// QA hook (the page exposes it only with ?qa in the address): clears the current level through
// the real rules by dropping the last coin on a free neighbouring square and stepping onto it.
@(export)
qa_clear_level :: proc "c" () {
	context = runtime.default_context()
	g := &state.rules
	if g.phase == .Title {
		game.begin(g)
	}
	for dir in ([?][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}) {
		c, r := g.column + dir.x, g.row + dir.y
		if c < 0 || r < 0 || c >= game.BOARD_COLUMNS || r >= game.BOARD_ROWS {
			continue
		}
		g.left = 1
		g.board[c][r] = .Gold
		game.move_dude(g, dir.x, dir.y)
		break
	}
	state.dirty = true
}
