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

// What the last move sounded like; the page plays it and clears it. Order is priority.
Sound :: enum u8 {
	None,
	Step,
	Ice,
	Shield, // fire absorbed by protection
	Coin,
	Level_Up,
	Death,
}

Phase :: enum u8 {
	Title,
	Playing,
	Level_Complete, // between levels: the next board is already dealt
	Game_Over,
}

// After dying, restart is refused for this many seconds so a key still being mashed cannot
// skip the game over screen.
GAME_OVER_DELAY :: 0.8

// Likewise for the screen between levels, so the next move cannot skip it.
LEVEL_COMPLETE_DELAY :: 0.6

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
	phase:      Phase,
	phase_time: f32, // seconds in this phase
	sound:      Sound,
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
	return next_random(&g.rng, count)
}

// xorshift64* on any state word, so the visual-only animation can have its own stream.
next_random :: proc(state: ^u64, count: int) -> int {
	state^ ~= state^ >> 12
	state^ ~= state^ << 25
	state^ ~= state^ >> 27
	return int((state^ * 0x2545F4914F6CDD1D) >> 33) % count
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
	g.phase = .Playing
	g.phase_time = 0
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
	if g.phase != .Playing {
		return
	}
	next_c, next_r := g.column + dx, g.row + dy
	if next_c < 0 || next_r < 0 || next_c >= BOARD_COLUMNS || next_r >= BOARD_ROWS {
		return
	}
	old_c, old_r := g.column, g.row
	g.sound = .Step
	#partial switch g.board[next_c][next_r] {
	case .Wall:
		g.sound = .None
		return
	case .Gold:
		g.left -= 1
		g.score += 1
		g.sound = .Coin
		if g.left == 0 {
			g.level += 1
			init_level(g)
			g.sound = .Level_Up
			g.phase = .Level_Complete
			g.phase_time = 0
		}
	case .Ice:
		g.protection += 1
		g.sound = .Ice
	case .Fire:
		if g.protection > 0 {
			g.protection -= 1
			g.sound = .Shield
		} else {
			g.alive = false
			g.sound = .Death
			g.phase = .Game_Over
			g.phase_time = 0
		}
	}
	g.board[old_c][old_r] = .Fire
	g.board[next_c][next_r] = g.alive ? .Dude : .Dead_Dude
	g.column, g.row = next_c, next_r
}

// Advances the clock. Returns true when a screen that waits for a key just became ready for it.
tick :: proc(g: ^Game, dt: f32) -> (became_ready: bool) {
	was_ready := input_ready(g)
	g.phase_time += dt
	return !was_ready && input_ready(g)
}

// True when the game over or between-levels screen has waited long enough to accept a key.
input_ready :: proc(g: ^Game) -> bool {
	switch g.phase {
	case .Game_Over:
		return g.phase_time >= GAME_OVER_DELAY
	case .Level_Complete:
		return g.phase_time >= LEVEL_COMPLETE_DELAY
	case .Title, .Playing:
	}
	return false
}

restart_ready :: proc(g: ^Game) -> bool {
	return g.phase == .Game_Over && input_ready(g)
}

// Leaves the title screen; the board behind it is already dealt.
begin :: proc(g: ^Game) -> bool {
	if g.phase != .Title {
		return false
	}
	g.phase = .Playing
	g.phase_time = 0
	return true
}

// Leaves the between-levels screen once it has waited long enough.
proceed :: proc(g: ^Game) -> bool {
	if g.phase != .Level_Complete || !input_ready(g) {
		return false
	}
	g.phase = .Playing
	g.phase_time = 0
	return true
}

// Starts a new game from the game over screen once the delay has passed.
restart :: proc(g: ^Game) -> bool {
	if !restart_ready(g) {
		return false
	}
	init_game(g)
	return true
}
