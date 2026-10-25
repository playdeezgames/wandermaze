package game

// Software renderer. Drawing is indexed (PALETTE entries); resolve() turns it into RGBA.
// Layout: the 17x17 board of 12 px Urizen icons on the left, a stats panel on the right.

TILE :: 12
SCREEN_WIDTH :: 340
SCREEN_HEIGHT :: 204

BOARD_PIXELS :: BOARD_COLUMNS * TILE // 204
PANEL_X :: BOARD_PIXELS
PANEL_PADDING :: 10

// Palette indices, see tools/extract_assets.py.
COLOR_BACKGROUND :: 0
COLOR_FLOOR :: 1
COLOR_LINE :: 2
COLOR_DIM :: 3
COLOR_WHITE :: 5
COLOR_ALIVE :: 9
COLOR_DEAD :: 7

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

fill_rect :: proc(f: ^Frame, x, y, w, h: int, color: u8) {
	for py in y ..< y + h {
		for px in x ..< x + w {
			put_pixel(f, px, py, color)
		}
	}
}

draw_icon :: proc(f: ^Frame, icon: Icon, x, y: int) {
	colors := ICON_COLORS[icon]
	for py in 0 ..< TILE {
		for px in 0 ..< TILE {
			if p := ICONS[icon][py * TILE + px]; p != 0 {
				put_pixel(f, x + px, y + py, colors[p - 1])
			}
		}
	}
}

// Columns of a glyph that hold at least one pixel, as [start, end); (0, 0) for a space.
glyph_span :: proc(ch: u8) -> (start, end: int) {
	used: u16
	for row in FONT[ch & 127] {
		used |= row
	}
	if used == 0 {
		return 0, 0
	}
	for start = 0; used >> uint(start) & 1 == 0; start += 1 {}
	for end = TILE; used >> uint(end - 1) & 1 == 0; end -= 1 {}
	return
}

SPACE_WIDTH :: 4
GLYPH_GAP :: 1

text_width :: proc(text: string) -> int {
	width := 0
	for i in 0 ..< len(text) {
		start, end := glyph_span(text[i])
		width += end > start ? end - start + GLYPH_GAP : SPACE_WIDTH
	}
	return max(0, width - GLYPH_GAP)
}

// Proportional text in the Urizen font: glyphs are trimmed to their used columns.
// Returns the width drawn.
draw_text :: proc(f: ^Frame, text: string, x, y: int, color: u8) -> int {
	pos := x
	for i in 0 ..< len(text) {
		ch := text[i]
		start, end := glyph_span(ch)
		if end <= start {
			pos += SPACE_WIDTH
			continue
		}
		for gy in 0 ..< TILE {
			for gx in start ..< end {
				if FONT[ch & 127][gy] >> uint(gx) & 1 != 0 {
					put_pixel(f, pos + gx - start, y + gy, color)
				}
			}
		}
		pos += end - start + GLYPH_GAP
	}
	return text_width(text)
}

format_int :: proc(buf: []u8, value: int) -> string {
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
	return string(buf[i:])
}

// Right edge of the stats panel's content.
PANEL_RIGHT :: SCREEN_WIDTH - PANEL_PADDING

draw_text_right :: proc(f: ^Frame, text: string, right, y: int, color: u8) {
	draw_text(f, text, right - text_width(text), y, color)
}

// One stat line: an icon, a label and the value flush right.
draw_stat :: proc(f: ^Frame, icon: Icon, label: string, value: int, y: int) {
	buf: [24]u8
	draw_icon(f, icon, PANEL_X + PANEL_PADDING, y)
	draw_text(f, label, PANEL_X + PANEL_PADDING + TILE + 6, y + 1, COLOR_DIM)
	draw_text_right(f, format_int(buf[:], value), PANEL_RIGHT, y + 1, COLOR_WHITE)
}

draw_cell :: proc(f: ^Frame, cell: Cell, c, r: int) {
	x, y := c * TILE, r * TILE
	floor: u8 = (c + r) % 2 == 0 ? COLOR_BACKGROUND : COLOR_FLOOR
	if cell == .Dude || cell == .Dead_Dude {
		floor = COLOR_LINE // the player's own square stands out
	}
	fill_rect(f, x, y, TILE, TILE, floor)
	#partial switch cell {
	case .Fire:
		draw_icon(f, .Fire, x, y)
	case .Ice:
		draw_icon(f, .Drop, x, y)
	case .Gold:
		draw_icon(f, .Coin, x, y)
	case .Wall:
		draw_icon(f, .Boulder, x, y)
	case .Dude:
		draw_icon(f, .Person, x, y)
	case .Dead_Dude:
		draw_icon(f, .Skeleton, x, y)
	}
}

draw_game :: proc(f: ^Frame, g: ^Game) {
	clear_frame(f, COLOR_BACKGROUND)
	for c in 0 ..< BOARD_COLUMNS {
		for r in 0 ..< BOARD_ROWS {
			draw_cell(f, g.board[c][r], c, r)
		}
	}

	// Stats panel.
	fill_rect(f, PANEL_X, 0, 1, SCREEN_HEIGHT, COLOR_LINE)
	buf: [24]u8
	left := PANEL_X + PANEL_PADDING
	draw_text(f, "LEVEL", left, 8, COLOR_DIM)
	draw_text_right(f, format_int(buf[:], g.level), PANEL_RIGHT, 8, COLOR_WHITE)
	fill_rect(f, left, 26, PANEL_RIGHT - left, 1, COLOR_LINE)

	if g.alive {
		draw_icon(f, .Person, left, 36)
		draw_text(f, "ALIVE", left + TILE + 6, 37, COLOR_ALIVE)
	} else {
		draw_icon(f, .Skeleton, left, 36)
		draw_text(f, "DEAD", left + TILE + 6, 37, COLOR_DEAD)
	}

	draw_stat(f, .Coin, "Coins left", g.left, 64)
	draw_stat(f, .Star, "Score", g.score, 88)
	draw_stat(f, .Drop, "Protection", g.protection, 112)

	if g.alive {
		draw_text(f, "Arrows: move", left, 176, COLOR_DIM)
		draw_text(f, "M: mute", left, 188, COLOR_DIM)
	} else {
		draw_text(f, "Press Enter", left, 176, COLOR_WHITE)
		draw_text(f, "to try again", left, 188, COLOR_WHITE)
	}
}

// Palette entries to RGBA bytes (R, G, B, 0xFF).
resolve :: proc(f: ^Frame) {
	for p, i in f.index {
		c := PALETTE[p & 15]
		f.rgba[i] = (c >> 16 & 0xFF) | (c >> 8 & 0xFF) << 8 | (c & 0xFF) << 16 | 0xFF << 24
	}
}
