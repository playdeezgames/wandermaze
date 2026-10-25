#+build !js
package game

import "core:os"
import "core:testing"

pixel :: proc(f: ^Frame, x, y: int) -> u8 {
	return f.index[y * SCREEN_WIDTH + x]
}

@(test)
text_is_proportional :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	start, end := glyph_span('A')
	testing.expect(t, end - start > 3 && end - start < 10)
	start, end = glyph_span(' ')
	testing.expect_value(t, end - start, 0)
	// 'i' and '!' are narrower than 'W'.
	_, wi := glyph_span('i')
	_, wW := glyph_span('W')
	testing.expect(t, wi < wW)
	testing.expect_value(t, draw_text(f, " ", 0, 0, COLOR_WHITE), SPACE_WIDTH - GLYPH_GAP)
	testing.expect_value(t, text_width("A A"), 2 * text_width("A") + SPACE_WIDTH + GLYPH_GAP)
	testing.expect_value(t, text_width(""), 0)
}

@(test)
text_clips_at_the_screen_edge :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	clear_frame(f, 0)
	draw_text(f, "Protection", SCREEN_WIDTH - 5, SCREEN_HEIGHT - 5, COLOR_WHITE)
	draw_text(f, "Protection", -20, -4, COLOR_WHITE)
	testing.expect(t, true) // no out-of-range write (bounds checks are on in tests)
}

@(test)
every_cell_draws_its_icon :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	g := blank_game()
	g.board[2][3] = .Fire
	g.board[3][3] = .Ice
	g.board[4][3] = .Gold
	g.board[5][3] = .Wall
	draw_game(f, &g)
	icons := [?]struct {
		c, r: int,
		icon: Icon,
	}{{2, 3, .Fire}, {3, 3, .Drop}, {4, 3, .Coin}, {5, 3, .Boulder}, {5, 5, .Person}}
	for want in icons {
		for py in 0 ..< TILE {
			for px in 0 ..< TILE {
				p := ICONS[want.icon][py * TILE + px]
				if p == 0 {
					continue
				}
				got := pixel(f, want.c * TILE + px, want.r * TILE + py)
				testing.expect_value(t, got, ICON_COLORS[want.icon][p - 1])
			}
		}
	}
	// The player's square is lighter than any floor.
	testing.expect_value(t, pixel(f, 5 * TILE, 5 * TILE), u8(COLOR_LINE))
	// An empty cell is just floor, alternating like a checkerboard.
	testing.expect_value(t, pixel(f, 0, 0), u8(COLOR_BACKGROUND))
	testing.expect_value(t, pixel(f, TILE, 0), u8(COLOR_FLOOR))
	g.alive = false
	g.board[g.column][g.row] = .Dead_Dude
	draw_game(f, &g)
	skeleton_pixels := 0
	for py in 0 ..< TILE {
		for px in 0 ..< TILE {
			if ICONS[Icon.Skeleton][py * TILE + px] != 0 {
				skeleton_pixels += 1
				testing.expect_value(t, pixel(f, g.column * TILE + px, g.row * TILE + py), ICON_COLORS[Icon.Skeleton][0])
			}
		}
	}
	testing.expect(t, skeleton_pixels > 10)
}

region_differs :: proc(a, b: ^Frame, x0, y0, x1, y1: int) -> bool {
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			if pixel(a, x, y) != pixel(b, x, y) {
				return true
			}
		}
	}
	return false
}

@(test)
panel_shows_state :: proc(t: ^testing.T) {
	a, b := new(Frame), new(Frame)
	defer free(a)
	defer free(b)
	g := blank_game()
	draw_game(a, &g)
	g.alive = false
	draw_game(b, &g)
	// The status line changes when the player dies.
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 30, SCREEN_WIDTH, 56))
	// Each stat changes its own line.
	g = blank_game()
	draw_game(a, &g)
	g.left, g.score, g.protection, g.level = 3, 13, 7, 4
	draw_game(b, &g)
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 0, SCREEN_WIDTH, 26)) // level
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 60, SCREEN_WIDTH, 84)) // coins left
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 84, SCREEN_WIDTH, 108)) // score
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 108, SCREEN_WIDTH, 132)) // protection
}

@(test)
numbers_stay_inside_the_panel :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	g := blank_game()
	g.left, g.score, g.protection, g.level = 16, 123456, 99999, 1000
	draw_game(f, &g)
	// Nothing but the panel's own line may be drawn to the right of PANEL_RIGHT.
	for y in 0 ..< SCREEN_HEIGHT {
		for x in PANEL_RIGHT ..< SCREEN_WIDTH {
			testing.expect_value(t, pixel(f, x, y), u8(COLOR_BACKGROUND))
		}
	}
}

@(test)
animation_replays_exactly_from_a_seed :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[3][3] = .Fire
	a, b: Animation
	init_animation(&a, 77)
	init_animation(&b, 77)
	for _ in 0 ..< 300 {
		step_animation(&a, &g, 1.0 / 60)
		step_animation(&b, &g, 1.0 / 60)
	}
	testing.expect(t, a == b)
	other: Animation
	init_animation(&other, 78)
	testing.expect(t, other.frame != a.frame)
}

@(test)
flames_start_out_of_step :: proc(t: ^testing.T) {
	a: Animation
	init_animation(&a, 5)
	seen: [FLAME_FRAMES]bool
	for column in a.frame {
		for frame in column {
			testing.expect(t, frame < FLAME_FRAMES)
			seen[frame] = true
		}
	}
	for s in seen {
		testing.expect(t, s) // every frame is in use somewhere on the board
	}
	for column in a.timer {
		for timer in column {
			testing.expect(t, timer >= FLICKER_FASTEST && timer <= FLICKER_SLOWEST)
		}
	}
}

@(test)
a_flame_changes_at_random_intervals :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[3][3] = .Fire
	a: Animation
	init_animation(&a, 9)
	changes := 0
	last := a.frame[3][3]
	gaps: [dynamic]int
	defer delete(gaps)
	since := 0
	for _ in 0 ..< 600 { // ten seconds at 60 Hz
		step_animation(&a, &g, 1.0 / 60)
		since += 1
		if a.frame[3][3] != last {
			last = a.frame[3][3]
			changes += 1
			append(&gaps, since)
			since = 0
		}
	}
	// 70 to 220 ms between changes: between 45 and 143 changes in ten seconds.
	testing.expect(t, changes > 45 && changes < 143)
	// The intervals are not all the same: that is the randomness.
	varied := false
	for gap in gaps {
		if gap != gaps[0] {
			varied = true
		}
	}
	testing.expect(t, varied)
}

@(test)
only_fire_squares_ask_for_a_redraw :: proc(t: ^testing.T) {
	g := blank_game() // no fire anywhere
	a: Animation
	init_animation(&a, 3)
	for _ in 0 ..< 300 {
		testing.expect(t, !step_animation(&a, &g, 1.0 / 60))
	}
	g.board[1][1] = .Fire
	redraws := 0
	for _ in 0 ..< 300 {
		if step_animation(&a, &g, 1.0 / 60) {
			redraws += 1
		}
	}
	testing.expect(t, redraws > 10)
}

@(test)
fire_draws_its_current_frame :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	g := blank_game()
	g.board[2][3] = .Fire
	a: Animation
	init_animation(&a, 1)
	for want in 0 ..< FLAME_FRAMES {
		a.frame[2][3] = u8(want)
		draw_game(f, &g, &a)
		icon := flame_icon(u8(want))
		for py in 0 ..< TILE {
			for px in 0 ..< TILE {
				if p := ICONS[icon][py * TILE + px]; p != 0 {
					testing.expect_value(t, pixel(f, 2 * TILE + px, 3 * TILE + py), ICON_COLORS[icon][p - 1])
				}
			}
		}
	}
	// The four frames really are different pictures.
	testing.expect(t, ICONS[Icon.Fire] != ICONS[Icon.Fire_1])
	testing.expect(t, ICONS[Icon.Fire_1] != ICONS[Icon.Fire_2])
	testing.expect(t, ICONS[Icon.Fire_2] != ICONS[Icon.Fire_3])
	testing.expect(t, ICONS[Icon.Fire_3] != ICONS[Icon.Fire])
}

@(test)
decorative_font_has_letters_only :: proc(t: ^testing.T) {
	for ch in "GAME OVERWandermaze" {
		if ch == ' ' {
			continue
		}
		start, end := glyph_span(u8(ch), true)
		testing.expect(t, end > start)
	}
	start, end := glyph_span('7', true)
	testing.expect_value(t, end - start, 0) // no digits in the decorative font
}

@(test)
scaled_text_is_wider_and_taller :: proc(t: ^testing.T) {
	testing.expect_value(t, text_width("Wandermaze", 3, true), 3 * text_width("Wandermaze", 1, true))
	f := new(Frame)
	defer free(f)
	clear_frame(f, 0)
	draw_text(f, "A", 10, 10, COLOR_WHITE, 3)
	lowest := 0
	for y in 0 ..< SCREEN_HEIGHT {
		for x in 0 ..< SCREEN_WIDTH {
			if pixel(f, x, y) == COLOR_WHITE {
				lowest = max(lowest, y)
			}
		}
	}
	testing.expect(t, lowest >= 10 + 3 * 9) // glyph rows reach the scaled height
}

@(test)
title_screen_has_no_board_and_blinks :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[3][3] = .Fire
	g.phase = .Title
	title, play := new(Frame), new(Frame)
	defer free(title)
	defer free(play)
	a: Animation
	init_animation(&a, 4)
	a.blink = true
	draw_game(title, &g, &a)
	g.phase = .Playing
	draw_game(play, &g, &a)
	testing.expect(t, region_differs(title, play, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT))
	// No stats panel line on the title screen.
	testing.expect_value(t, pixel(title, PANEL_X, 100), u8(COLOR_BACKGROUND))
	// The prompt is there while blinking on and gone while off.
	g.phase = .Title
	blink_on, blink_off := new(Frame), new(Frame)
	defer free(blink_on)
	defer free(blink_off)
	draw_game(blink_on, &g, &a)
	a.blink = false
	draw_game(blink_off, &g, &a)
	testing.expect(t, region_differs(blink_on, blink_off, 0, 160, SCREEN_WIDTH, 184))
	testing.expect(t, !region_differs(blink_on, blink_off, 0, 0, SCREEN_WIDTH, 160)) // flames unchanged
}

@(test)
blinking_asks_for_redraws_only_off_the_playing_screen :: proc(t: ^testing.T) {
	g := blank_game() // playing, no fire
	a: Animation
	init_animation(&a, 8)
	for _ in 0 ..< 120 {
		testing.expect(t, !step_animation(&a, &g, 1.0 / 60))
	}
	g.phase = .Title
	redraws := 0
	for _ in 0 ..< 120 { // two seconds: about five blinks
		if step_animation(&a, &g, 1.0 / 60) {
			redraws += 1
		}
	}
	testing.expect(t, redraws >= 4)
}

@(test)
game_over_box_shows_stats_and_prompt_after_the_delay :: proc(t: ^testing.T) {
	g := blank_game()
	g.level, g.score = 3, 41
	g.board[5][6] = .Fire
	move_dude(&g, 0, 1)
	testing.expect_value(t, g.phase, Phase.Game_Over)
	a: Animation
	init_animation(&a, 2)
	a.blink = true
	early, ready, play := new(Frame), new(Frame), new(Frame)
	defer free(early)
	defer free(ready)
	defer free(play)
	draw_game(early, &g, &a)
	tick(&g, GAME_OVER_DELAY + 0.1)
	draw_game(ready, &g, &a)
	g.phase = .Playing
	draw_game(play, &g, &a)
	// The player died on row 6 (upper half), so the box sits at the bottom of the board.
	box := BOARD_PIXELS - 92 - 4
	testing.expect(t, region_differs(early, play, 6, box, BOARD_PIXELS - 6, BOARD_PIXELS - 4))
	testing.expect(t, region_differs(early, ready, 6, box + 70, BOARD_PIXELS - 6, box + 90)) // prompt row
	testing.expect(t, !region_differs(early, ready, 6, box, BOARD_PIXELS - 6, box + 70)) // text rows
	// The skeleton stays visible, outside the box.
	for py in 0 ..< TILE {
		for px in 0 ..< TILE {
			if ICONS[Icon.Skeleton][py * TILE + px] != 0 {
				testing.expect_value(t, pixel(ready, g.column * TILE + px, g.row * TILE + py), ICON_COLORS[Icon.Skeleton][0])
			}
		}
	}
	// Dying in the lower half moves the box to the top.
	g = blank_game()
	g.row = 12
	init_board(&g)
	g.board[5][13] = .Fire
	move_dude(&g, 0, 1)
	draw_game(play, &g, &a)
	testing.expect_value(t, pixel(play, 6, 4), u8(COLOR_LINE)) // top-left corner of the box
	testing.expect(t, pixel(play, 6, BOARD_PIXELS - 5) != COLOR_LINE) // nothing at the bottom
}

@(test)
resolve_maps_palette_to_rgba_bytes :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	clear_frame(f, 7) // 0xe8463c
	resolve(f)
	bytes := (^[4]u8)(&f.rgba[0])^
	testing.expect_value(t, bytes, [4]u8{0xe8, 0x46, 0x3c, 0xff})
}

// Not real tests: `odin test ... -define:DUMP_FRAME=a.ppm -define:DUMP_FRAME_DEAD=b.ppm` write
// seeded frames (a fresh game, and the same game after stepping onto its own fire) for
// tools/make_assets.sh.
DUMP_FRAME :: #config(DUMP_FRAME, "")
DUMP_FRAME_DEAD :: #config(DUMP_FRAME_DEAD, "")
DUMP_FRAME_TITLE :: #config(DUMP_FRAME_TITLE, "")

write_ppm :: proc(t: ^testing.T, path: string, f: ^Frame) {
	resolve(f)
	out := make([dynamic]u8)
	defer delete(out)
	append(&out, "P6\n340 204\n255\n")
	for px in f.rgba {
		append(&out, u8(px), u8(px >> 8), u8(px >> 16))
	}
	testing.expect_value(t, os.write_entire_file(path, out[:]), nil)
}

@(test)
dump_frames :: proc(t: ^testing.T) {
	if DUMP_FRAME == "" && DUMP_FRAME_DEAD == "" && DUMP_FRAME_TITLE == "" {
		return
	}
	f := new(Frame)
	defer free(f)
	g: Game
	seed_game(&g, 1)
	init_game(&g)
	flames: Animation
	init_animation(&flames, 1)
	flames.blink = true
	if DUMP_FRAME_TITLE != "" {
		g.phase = .Title
		draw_game(f, &g, &flames)
		write_ppm(t, DUMP_FRAME_TITLE, f)
		g.phase = .Playing
	}
	if DUMP_FRAME != "" {
		draw_game(f, &g, &flames)
		write_ppm(t, DUMP_FRAME, f)
	}
	if DUMP_FRAME_DEAD != "" {
		// Step onto a free neighbour and straight back: the cell just left is fire.
		for dir in ([?][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			before := g.column
			before_row := g.row
			move_dude(&g, dir.x, dir.y)
			if g.column != before || g.row != before_row {
				if g.alive {
					move_dude(&g, -dir.x, -dir.y)
				}
				break
			}
		}
		testing.expect(t, !g.alive)
		tick(&g, GAME_OVER_DELAY + 0.1) // so the prompt shows
		draw_game(f, &g, &flames)
		write_ppm(t, DUMP_FRAME_DEAD, f)
	}
}
