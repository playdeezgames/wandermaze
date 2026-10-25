#+build !js
package game

import "core:os"
import "core:testing"

pixel :: proc(f: ^Frame, x, y: int) -> u8 {
	return f.index[y * SCREEN_WIDTH + x]
}

@(test)
glyph_widths_follow_tic80_rules :: proc(t: ^testing.T) {
	start, end := glyph_span('A')
	testing.expect_value(t, end - start, 5)
	start, end = glyph_span(' ')
	testing.expect_value(t, end - start, 0)
	start, end = glyph_span('!')
	testing.expect_value(t, end - start, 2)
}

@(test)
text_advance_is_proportional :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	testing.expect_value(t, draw_text(f, "A", 0, 0), 6) // 5 wide + 1
	testing.expect_value(t, draw_text(f, "!", 0, 0), 3) // 2 wide + 1
	testing.expect_value(t, draw_text(f, " ", 0, 0), 4) // empty glyph
	testing.expect_value(t, draw_text(f, "A A", 0, 0), 16)
}

@(test)
text_clips_at_the_screen_edge :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	clear_frame(f, 0)
	draw_text(f, "Status:", SCREEN_WIDTH - 3, SCREEN_HEIGHT - 3)
	draw_text(f, "Status:", -20, -4)
	testing.expect(t, true) // no out-of-range write (bounds checks are on in tests)
}

@(test)
sprite_pixels_land_on_the_grid :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	g := blank_game()
	g.board[2][3] = .Fire
	draw_game(f, &g)
	// Cell (2, 3) starts at pixel (16, 24); the fire sprite's tip is at its column 4, row 0.
	testing.expect_value(t, pixel(f, 16 + 4, 24), u8(2))
	testing.expect_value(t, pixel(f, 16, 24), u8(11))
	// The dude at (5, 5): sprite 3 has a dark eye pixel at (2, 2).
	testing.expect_value(t, pixel(f, 5 * 8 + 2, 5 * 8 + 2), u8(0))
	// Right of the board is the HUD background.
	testing.expect_value(t, pixel(f, HUD_X + 100, 120), u8(CLEAR_COLOR))
}

@(test)
hud_shows_state :: proc(t: ^testing.T) {
	alive, dead := new(Frame), new(Frame)
	defer free(alive)
	defer free(dead)
	g := blank_game()
	draw_game(alive, &g)
	g.alive = false
	draw_game(dead, &g)
	differs := false
	for y in 8 ..< 16 {
		for x in HUD_X ..< SCREEN_WIDTH {
			if pixel(alive, x, y) != pixel(dead, x, y) {
				differs = true
			}
		}
	}
	testing.expect(t, differs)
	// "Status:" is drawn in colour 15 starting at the HUD column.
	found := false
	for y in 0 ..< 8 {
		if pixel(alive, HUD_X, y) == TEXT_COLOR || pixel(alive, HUD_X + 1, y) == TEXT_COLOR {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
resolve_maps_palette_to_rgba_bytes :: proc(t: ^testing.T) {
	f := new(Frame)
	defer free(f)
	clear_frame(f, 2) // 0xb13e53
	resolve(f)
	bytes := (^[4]u8)(&f.rgba[0])^
	testing.expect_value(t, bytes, [4]u8{0xb1, 0x3e, 0x53, 0xff})
}

// Not a real test: `odin test ... -define:DUMP_FRAME=path.ppm` writes a seeded frame for eyeballing.
DUMP_FRAME :: #config(DUMP_FRAME, "")

@(test)
dump_frame :: proc(t: ^testing.T) {
	if DUMP_FRAME == "" {
		return
	}
	f := new(Frame)
	defer free(f)
	g: Game
	seed_game(&g, 1)
	init_game(&g)
	draw_game(f, &g)
	resolve(f)
	out := make([dynamic]u8)
	defer delete(out)
	append(&out, "P6\n240 136\n255\n")
	for px in f.rgba {
		append(&out, u8(px), u8(px >> 8), u8(px >> 16))
	}
	testing.expect_value(t, os.write_entire_file(DUMP_FRAME, out[:]), nil)
}
