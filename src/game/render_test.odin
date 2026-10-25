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
	// The status line and the bottom hint change when the player dies.
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 30, SCREEN_WIDTH, 56))
	testing.expect(t, region_differs(a, b, PANEL_X + 8, 170, SCREEN_WIDTH, SCREEN_HEIGHT))
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
	if DUMP_FRAME == "" && DUMP_FRAME_DEAD == "" {
		return
	}
	f := new(Frame)
	defer free(f)
	g: Game
	seed_game(&g, 1)
	init_game(&g)
	if DUMP_FRAME != "" {
		draw_game(f, &g)
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
		draw_game(f, &g)
		write_ppm(t, DUMP_FRAME_DEAD, f)
	}
}
