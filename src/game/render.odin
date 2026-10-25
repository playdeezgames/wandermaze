package game

// Software renderer reproducing the cart's TIC() draw: cls(0), board sprites, HUD text.
// Drawing is indexed (palette entries); resolve() turns it into RGBA for the page.

SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 136

HUD_X :: BOARD_COLUMNS * 8 // 136
CLEAR_COLOR :: 0
TEXT_COLOR :: 15 // print() default; dark slate on near-black, exactly as the original looks.

Frame :: struct {
	index: [SCREEN_WIDTH * SCREEN_HEIGHT]u8,
	rgba:  [SCREEN_WIDTH * SCREEN_HEIGHT]u32, // bytes R,G,B,A in memory
}

clear_frame :: proc(f: ^Frame, color: u8) {
	for &p in f.index {
		p = color
	}
}

put_pixel :: proc(f: ^Frame, x, y: int, color: u8) {
	if x < 0 || y < 0 || x >= SCREEN_WIDTH || y >= SCREEN_HEIGHT {
		return
	}
	f.index[y * SCREEN_WIDTH + x] = color
}

// spr() without a colorkey: every pixel is drawn, including colour 0.
draw_sprite :: proc(f: ^Frame, sprite: int, x, y: int) {
	for py in 0 ..< 8 {
		for px in 0 ..< 8 {
			put_pixel(f, x + px, y + py, SPRITES[sprite][py * 8 + px])
		}
	}
}

// Columns of a glyph that hold at least one pixel, as [start, end).
glyph_span :: proc(ch: u8) -> (start, end: int) {
	used: u8
	for row in FONT[ch & 127] {
		used |= row
	}
	if used == 0 {
		return 8, 8
	}
	for start = 0; used >> uint(start) & 1 == 0; start += 1 {}
	for end = 8; used >> uint(end - 1) & 1 == 0; end -= 1 {}
	return
}

// print() with fixed=false, scale=1: glyphs are trimmed to their used columns and
// advance by width + 1; an empty glyph (space) advances 4. Returns the width drawn.
draw_text :: proc(f: ^Frame, text: string, x, y: int, color: u8 = TEXT_COLOR) -> int {
	pos := x
	for i in 0 ..< len(text) {
		ch := text[i]
		start, end := glyph_span(ch)
		width := end - start
		for gx in 0 ..< width {
			for gy in 0 ..< 8 {
				if FONT[ch & 127][gy] >> uint(start + gx) & 1 != 0 {
					put_pixel(f, pos + gx, y + gy, color)
				}
			}
		}
		pos += width > 0 ? width + 1 : 4
	}
	return pos - x
}

// Lua's print(number): decimal integer.
draw_int :: proc(f: ^Frame, value: int, x, y: int) -> int {
	buf: [24]u8
	i := len(buf)
	v := value < 0 ? -value : value
	for {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
		if v == 0 {
			break
		}
	}
	if value < 0 {
		i -= 1
		buf[i] = '-'
	}
	return draw_text(f, string(buf[i:]), x, y)
}

draw_game :: proc(f: ^Frame, g: ^Game) {
	clear_frame(f, CLEAR_COLOR)
	for c in 0 ..< BOARD_COLUMNS {
		for r in 0 ..< BOARD_ROWS {
			draw_sprite(f, int(g.board[c][r]), c * 8, r * 8)
		}
	}
	draw_text(f, "Status:", HUD_X, 0)
	draw_text(f, g.alive ? "ALIVE" : "DEAD!", HUD_X, 8)
	draw_text(f, "Left:", HUD_X, 24)
	draw_int(f, g.left, HUD_X, 32)
	draw_text(f, "Score:", HUD_X, 48)
	draw_int(f, g.score, HUD_X, 56)
	draw_text(f, "Protection:", HUD_X, 72)
	draw_int(f, g.protection, HUD_X, 80)
	draw_text(f, "Level:", HUD_X, 96)
	draw_int(f, g.level, HUD_X, 104)
}

// Palette entries to RGBA bytes (R, G, B, 0xFF).
resolve :: proc(f: ^Frame) {
	for p, i in f.index {
		c := PALETTE[p & 15]
		f.rgba[i] = (c >> 16 & 0xFF) | (c >> 8 & 0xFF) << 8 | (c & 0xFF) << 16 | 0xFF << 24
	}
}
