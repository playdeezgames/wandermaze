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
glyph_span :: proc(ch: u8, decor := false) -> (start, end: int) {
	used: u16
	for row in (decor ? DECOR_FONT[ch & 127] : FONT[ch & 127]) {
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

text_width :: proc(text: string, scale := 1, decor := false) -> int {
	width := 0
	for i in 0 ..< len(text) {
		start, end := glyph_span(text[i], decor)
		width += (end > start ? end - start + GLYPH_GAP : SPACE_WIDTH) * scale
	}
	return max(0, width - GLYPH_GAP * scale)
}

// Proportional text in the Urizen font (or its decorative font, which has letters only):
// glyphs are trimmed to their used columns, every pixel becomes scale x scale. Returns the width.
draw_text :: proc(f: ^Frame, text: string, x, y: int, color: u8, scale := 1, decor := false) -> int {
	pos := x
	for i in 0 ..< len(text) {
		ch := text[i]
		start, end := glyph_span(ch, decor)
		if end <= start {
			pos += SPACE_WIDTH * scale
			continue
		}
		glyph := decor ? DECOR_FONT[ch & 127] : FONT[ch & 127]
		for gy in 0 ..< TILE {
			for gx in start ..< end {
				if glyph[gy] >> uint(gx) & 1 != 0 {
					fill_rect(f, pos + (gx - start) * scale, y + gy * scale, scale, scale, color)
				}
			}
		}
		pos += (end - start + GLYPH_GAP) * scale
	}
	return text_width(text, scale, decor)
}

draw_text_centered :: proc(f: ^Frame, text: string, center_x, y: int, color: u8, scale := 1, decor := false) {
	draw_text(f, text, center_x - text_width(text, scale, decor) / 2, y, color, scale, decor)
}

draw_icon_scaled :: proc(f: ^Frame, icon: Icon, x, y, scale: int) {
	colors := ICON_COLORS[icon]
	for py in 0 ..< TILE {
		for px in 0 ..< TILE {
			if p := ICONS[icon][py * TILE + px]; p != 0 {
				fill_rect(f, x + px * scale, y + py * scale, scale, scale, colors[p - 1])
			}
		}
	}
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

// Visual-only state: each square's flame frame and how long until it changes. It has its own
// random stream, so flicker never disturbs the rules' RNG and tests can replay it exactly.
FLAME_FRAMES :: 4
FLICKER_FASTEST :: 0.07 // seconds between frame changes: 70 ms ...
FLICKER_SLOWEST :: 0.22 // ... to 220 ms, random for every change

Animation :: struct {
	frame: [BOARD_COLUMNS][BOARD_ROWS]u8,
	timer: [BOARD_COLUMNS][BOARD_ROWS]f32,
	rng:   u64,
	clock: f32, // seconds, drives the blinking prompts
	blink: bool,
}

init_animation :: proc(a: ^Animation, seed: u64) {
	a.rng = seed != 0 ? seed : 0x2545F4914F6CDD1D
	for c in 0 ..< BOARD_COLUMNS {
		for r in 0 ..< BOARD_ROWS {
			a.frame[c][r] = u8(next_random(&a.rng, FLAME_FRAMES))
			a.timer[c][r] = flicker_delay(a)
		}
	}
}

flicker_delay :: proc(a: ^Animation) -> f32 {
	return FLICKER_FASTEST + (FLICKER_SLOWEST - FLICKER_FASTEST) * f32(next_random(&a.rng, 1000)) / 1000
}

// Advances every square's timer by dt seconds. A flame jumps to a random other frame when its
// timer runs out, and goes back to the calm frame 0 four times in ten. Returns true when a
// square that is on fire changed, i.e. when the picture needs redrawing.
BLINKS_PER_SECOND :: 2.5

step_animation :: proc(a: ^Animation, g: ^Game, dt: f32) -> (changed: bool) {
	a.clock += dt
	if blink := int(a.clock * BLINKS_PER_SECOND) % 2 == 0; blink != a.blink {
		a.blink = blink
		changed ||= g.phase != .Playing // only the title and game over prompts blink
	}
	for c in 0 ..< BOARD_COLUMNS {
		for r in 0 ..< BOARD_ROWS {
			a.timer[c][r] -= dt
			if a.timer[c][r] > 0 {
				continue
			}
			old := a.frame[c][r]
			next := u8((int(old) + 1 + next_random(&a.rng, FLAME_FRAMES - 1)) % FLAME_FRAMES)
			if old != 0 && next_random(&a.rng, 10) < 4 {
				next = 0
			}
			a.frame[c][r] = next
			a.timer[c][r] = flicker_delay(a)
			// The two flames beside the title screen's name use the top-left squares' frames.
			on_title := g.phase == .Title && r == 0 && c < 2
			if next != old && (g.board[c][r] == .Fire && g.phase != .Title || on_title) {
				changed = true
			}
		}
	}
	return
}

flame_icon :: proc(frame: u8) -> Icon {
	switch frame % FLAME_FRAMES {
	case 1:
		return .Fire_1
	case 2:
		return .Fire_2
	case 3:
		return .Fire_3
	}
	return .Fire
}

draw_cell :: proc(f: ^Frame, cell: Cell, c, r: int, flame: Icon) {
	x, y := c * TILE, r * TILE
	floor: u8 = (c + r) % 2 == 0 ? COLOR_BACKGROUND : COLOR_FLOOR
	if cell == .Dude || cell == .Dead_Dude {
		floor = COLOR_LINE // the player's own square stands out
	}
	fill_rect(f, x, y, TILE, TILE, floor)
	#partial switch cell {
	case .Fire:
		draw_icon(f, flame, x, y)
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

COLOR_TITLE :: 7
COLOR_COIN :: 6

draw_title :: proc(f: ^Frame, animation: ^Animation) {
	clear_frame(f, COLOR_BACKGROUND)
	center := SCREEN_WIDTH / 2
	width := draw_text(f, "Wandermaze", center - text_width("Wandermaze", 3, true) / 2, 22, COLOR_TITLE, 3, true)
	flame_left, flame_right := Icon.Fire, Icon.Fire_2
	if animation != nil {
		flame_left, flame_right = flame_icon(animation.frame[0][0]), flame_icon(animation.frame[1][0])
	}
	draw_icon(f, flame_left, center - width / 2 - TILE - 8, 34)
	draw_icon(f, flame_right, center + width / 2 + 8, 34)
	draw_text_centered(f, "The maze closes behind you.", center, 70, COLOR_WHITE)

	legend := [?]struct {
		icon: Icon,
		text: string,
	}{
		{.Coin, "Collect all 16 coins to climb a level"},
		{.Drop, "Ice protects you from one fire"},
		{.Fire, "Every square you leave turns to fire"},
		{.Boulder, "Boulders block your way"},
	}
	for line, i in legend {
		y := 96 + i * 16
		draw_icon(f, line.icon, 28, y)
		draw_text(f, line.text, 28 + TILE + 8, y + 1, 4)
	}
	if animation == nil || animation.blink {
		draw_text_centered(f, "Press Enter or tap to start", center, 168, COLOR_WHITE)
	}
	draw_text_centered(f, "Icons: Urizen by vurmux (CC0)", center, 190, COLOR_DIM)
}

// A box over the board, on the half that does not hide the skeleton.
draw_game_over :: proc(f: ^Frame, g: ^Game, animation: ^Animation) {
	box_x, box_w, box_h := 6, BOARD_PIXELS - 12, 92
	box_y := g.row <= BOARD_ROWS / 2 ? BOARD_PIXELS - box_h - 4 : 4
	fill_rect(f, box_x, box_y, box_w, box_h, COLOR_LINE)
	fill_rect(f, box_x + 2, box_y + 2, box_w - 4, box_h - 4, COLOR_BACKGROUND)
	center := box_x + box_w / 2
	draw_text_centered(f, "GAME OVER", center, box_y + 8, COLOR_TITLE, 2, true)
	buf: [24]u8
	line: [48]u8
	draw_text_centered(f, join_number(line[:], "Level ", g.level, buf[:]), center, box_y + 42, COLOR_WHITE)
	draw_text_centered(f, join_number(line[:], "Score ", g.score, buf[:]), center, box_y + 56, COLOR_WHITE)
	if restart_ready(g) && (animation == nil || animation.blink) {
		draw_text_centered(f, "Press Enter", center, box_y + 74, COLOR_ALIVE)
	}
}

// "Fire 48" style groups, icon then number, laid out in one centred row.
draw_icon_counts :: proc(f: ^Frame, counts: []struct {
		icon:  Icon,
		count: int,
	}, center_x, y: int) {
	GAP :: 18
	buf: [24]u8
	total := -GAP
	for item in counts {
		total += TILE + 4 + text_width(format_int(buf[:], item.count)) + GAP
	}
	x := center_x - total / 2
	for item in counts {
		draw_icon(f, item.icon, x, y)
		text := format_int(buf[:], item.count)
		draw_text(f, text, x + TILE + 4, y + 1, COLOR_WHITE)
		x += TILE + 4 + text_width(text) + GAP
	}
}

// Between levels: what carries over and what the next board holds. The board is already dealt.
draw_level_complete :: proc(f: ^Frame, g: ^Game, animation: ^Animation) {
	clear_frame(f, COLOR_BACKGROUND)
	center := SCREEN_WIDTH / 2
	width := draw_text(f, "Level cleared", center - text_width("Level cleared", 2, true) / 2, 14, COLOR_COIN, 2, true)
	draw_icon(f, .Coin, center - width / 2 - TILE - 10, 20)
	draw_icon(f, .Coin, center + width / 2 + 10, 20)
	buf: [24]u8
	line: [48]u8
	draw_text_centered(f, join_number(line[:], "You cleared level ", g.level - 1, buf[:]), center, 52, COLOR_WHITE)

	// What you keep.
	left, right := 84, SCREEN_WIDTH - 84
	draw_icon(f, .Star, left, 84)
	draw_text(f, "Score", left + TILE + 6, 85, COLOR_DIM)
	draw_text_right(f, format_int(buf[:], g.score), right, 85, COLOR_WHITE)
	draw_icon(f, .Drop, left, 102)
	draw_text(f, "Protection", left + TILE + 6, 103, COLOR_DIM)
	draw_text_right(f, format_int(buf[:], g.protection), right, 103, COLOR_WHITE)
	fill_rect(f, left, 124, right - left, 1, COLOR_LINE)

	// What is coming.
	draw_text_centered(f, join_number(line[:], "Next: level ", g.level, buf[:]), center, 132, COLOR_WHITE)
	draw_icon_counts(f, []struct {
		icon:  Icon,
		count: int,
	}{{.Coin, coin_count(g.level)}, {.Fire, fire_count(g.level)}, {.Boulder, wall_count(g.level)}, {.Drop, ice_count(g.level)}}, center, 152)

	if input_ready(g) && (animation == nil || animation.blink) {
		draw_text_centered(f, "Press Enter to continue", center, 182, COLOR_ALIVE)
	}
}

join_number :: proc(buf: []u8, prefix: string, value: int, scratch: []u8) -> string {
	digits := format_int(scratch, value)
	n := copy(buf, prefix)
	n += copy(buf[n:], digits)
	return string(buf[:n])
}

// The animation is optional: without one every flame shows its calm frame and prompts show.
draw_game :: proc(f: ^Frame, g: ^Game, animation: ^Animation = nil) {
	if g.phase == .Title {
		draw_title(f, animation)
		return
	}
	if g.phase == .Level_Complete {
		draw_level_complete(f, g, animation)
		return
	}
	clear_frame(f, COLOR_BACKGROUND)
	for c in 0 ..< BOARD_COLUMNS {
		for r in 0 ..< BOARD_ROWS {
			flame := Icon.Fire
			if animation != nil {
				flame = flame_icon(animation.frame[c][r])
			}
			draw_cell(f, g.board[c][r], c, r, flame)
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

	draw_text(f, "Arrows: move", left, 176, COLOR_DIM)
	draw_text(f, "M: mute", left, 188, COLOR_DIM)

	if g.phase == .Game_Over {
		draw_game_over(f, g, animation)
	}
}

// Palette entries to RGBA bytes (R, G, B, 0xFF).
resolve :: proc(f: ^Frame) {
	for p, i in f.index {
		c := PALETTE[p & 15]
		f.rgba[i] = (c >> 16 & 0xFF) | (c >> 8 & 0xFF) << 8 | (c & 0xFF) << 16 | 0xFF << 24
	}
}
