package game

// Port of the TIC-80 cart's Lua rules. Pure: no platform imports, no clock.
// Coordinates are 0-based here (the Lua is 1-based); the board is [column][row].

BOARD_COLUMNS :: 17
BOARD_ROWS :: 17

// The value of a cell is its sprite index in SPRITES.
Cell :: enum u8 {
	Blank, // sprite 0; never on the board
	Empty,
	Fire,
	Dude,
	Ice,
	Gold,
	Wall,
	Dead_Dude,
}

Game :: struct {
	board:      [BOARD_COLUMNS][BOARD_ROWS]Cell,
	column:     int,
	row:        int,
	score:      int,
	left:       int, // coins left on this level
	protection: int,
	level:      int,
	moves:      int, // never updated by the original either
	alive:      bool,
	rng:        u64,
}

coin_count :: proc(level: int) -> int {
	return 16
}

fire_count :: proc(level: int) -> int {
	return 32 + 16 * (level - 1)
}

ice_count :: proc(level: int) -> int {
	return max(1, 4 - (level - 1) / 2)
}

wall_count :: proc(level: int) -> int {
	return 4 + 2 * (level - 1)
}

// xorshift64*; the caller seeds it, so tests are deterministic.
seed_game :: proc(g: ^Game, seed: u64) {
	g.rng = seed != 0 ? seed : 0x9E3779B97F4A7C15
}

random_range :: proc(g: ^Game, count: int) -> int {
	g.rng ~= g.rng >> 12
	g.rng ~= g.rng << 25
	g.rng ~= g.rng >> 27
	return int((g.rng * 0x2545F4914F6CDD1D) >> 33) % count
}

init_board :: proc(g: ^Game) {
	for &column in g.board {
		for &cell in column {
			cell = .Empty
		}
	}
	g.board[g.column][g.row] = .Dude
}

// The original loops forever when the board is full (around level 14); this
// gives up instead, so a late level just has fewer things on it.
place :: proc(g: ^Game, thing: Cell) -> bool {
	empty := 0
	for column in g.board {
		for cell in column {
			if cell == .Empty {
				empty += 1
			}
		}
	}
	if empty == 0 {
		return false
	}
	for {
		c := random_range(g, BOARD_COLUMNS)
		r := random_range(g, BOARD_ROWS)
		if g.board[c][r] == .Empty {
			g.board[c][r] = thing
			return true
		}
	}
}

init_level :: proc(g: ^Game) {
	init_board(g)
	g.left = coin_count(g.level)
	for _ in 0 ..< coin_count(g.level) {
		place(g, .Gold)
	}
	for _ in 0 ..< fire_count(g.level) {
		place(g, .Fire)
	}
	for _ in 0 ..< ice_count(g.level) {
		place(g, .Ice)
	}
	for _ in 0 ..< wall_count(g.level) {
		place(g, .Wall)
	}
}

// Starts a new game; the RNG state carries on from whatever it was (seed first).
init_game :: proc(g: ^Game) {
	g.score = 0
	g.alive = true
	g.protection = 0
	g.level = 1
	g.moves = 0
	g.column = random_range(g, BOARD_COLUMNS)
	g.row = random_range(g, BOARD_ROWS)
	init_level(g)
}

// One step. Order of effects matches the original, quirks included: finishing
// the last coin rebuilds the board around the OLD position before the old cell
// is set to fire and the dude is put on the new one (so a coin generated on the
// destination cell is overwritten and can never be collected).
move_dude :: proc(g: ^Game, dx, dy: int) {
	next_c, next_r := g.column + dx, g.row + dy
	if next_c < 0 || next_r < 0 || next_c >= BOARD_COLUMNS || next_r >= BOARD_ROWS {
		return
	}
	old_c, old_r := g.column, g.row
	#partial switch g.board[next_c][next_r] {
	case .Wall:
		return
	case .Gold:
		g.left -= 1
		g.score += 1
		if g.left == 0 {
			g.level += 1
			init_level(g)
		}
	case .Ice:
		g.protection += 1
	case .Fire:
		if g.protection > 0 {
			g.protection -= 1
		} else {
			g.alive = false
		}
	}
	g.board[old_c][old_r] = .Fire
	g.board[next_c][next_r] = g.alive ? .Dude : .Dead_Dude
	g.column, g.row = next_c, next_r
}
