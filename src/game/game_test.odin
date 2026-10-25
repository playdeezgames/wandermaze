#+build !js
package game

import "core:testing"

// An all-empty board with the dude at (5, 5): tests then drop what they need around him.
blank_game :: proc() -> Game {
	g: Game
	seed_game(&g, 42)
	g.alive = true
	g.level = 1
	g.left = 16
	g.column, g.row = 5, 5
	init_board(&g)
	return g
}

tally :: proc(g: ^Game) -> (counts: [Cell]int) {
	for column in g.board {
		for cell in column {
			counts[cell] += 1
		}
	}
	return
}

@(test)
level_formulas :: proc(t: ^testing.T) {
	testing.expect_value(t, coin_count(1), 16)
	testing.expect_value(t, coin_count(9), 16)
	testing.expect_value(t, fire_count(1), 32)
	testing.expect_value(t, fire_count(3), 64)
	testing.expect_value(t, wall_count(1), 4)
	testing.expect_value(t, wall_count(5), 12)
	// 4,4,3,3,2,2,1,1,1 ...
	expected := [?]int{4, 4, 3, 3, 2, 2, 1, 1, 1, 1}
	for want, i in expected {
		testing.expect_value(t, ice_count(i + 1), want)
	}
}

@(test)
new_game_has_level_one_contents :: proc(t: ^testing.T) {
	g: Game
	seed_game(&g, 7)
	init_game(&g)
	counts := tally(&g)
	testing.expect_value(t, counts[.Gold], 16)
	testing.expect_value(t, counts[.Fire], 32)
	testing.expect_value(t, counts[.Ice], 4)
	testing.expect_value(t, counts[.Wall], 4)
	testing.expect_value(t, counts[.Dude], 1)
	testing.expect_value(t, counts[.Dead_Dude], 0)
	testing.expect_value(t, g.board[g.column][g.row], Cell.Dude)
	testing.expect_value(t, g.left, 16)
	testing.expect(t, g.alive && g.score == 0 && g.protection == 0 && g.level == 1)
}

@(test)
placement_never_overlaps_and_fits_until_the_board_is_full :: proc(t: ^testing.T) {
	g: Game
	seed_game(&g, 99)
	init_game(&g)
	for level in 1 ..= 14 {
		g.level = level
		init_level(&g)
		counts := tally(&g)
		testing.expect_value(t, counts[.Gold], coin_count(level))
		testing.expect_value(t, counts[.Fire], fire_count(level))
		testing.expect_value(t, counts[.Ice], ice_count(level))
		testing.expect_value(t, counts[.Wall], wall_count(level))
		testing.expect_value(t, counts[.Dude], 1)
	}
	// The original hangs here; the port fills the board and stops.
	g.level = 15
	init_level(&g)
	testing.expect_value(t, tally(&g)[.Empty], 0)
}

@(test)
same_seed_same_board :: proc(t: ^testing.T) {
	a, b: Game
	seed_game(&a, 1234)
	seed_game(&b, 1234)
	init_game(&a)
	init_game(&b)
	testing.expect(t, a.board == b.board && a.column == b.column && a.row == b.row)
}

@(test)
edges_block_movement :: proc(t: ^testing.T) {
	dirs := [?][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}
	starts := [?][2]int{{5, 0}, {5, BOARD_ROWS - 1}, {0, 5}, {BOARD_COLUMNS - 1, 5}}
	for dir, i in dirs {
		g := blank_game()
		g.column, g.row = starts[i].x, starts[i].y
		init_board(&g)
		move_dude(&g, dir.x, dir.y)
		testing.expect_value(t, g.column, starts[i].x)
		testing.expect_value(t, g.row, starts[i].y)
		testing.expect_value(t, tally(&g)[.Fire], 0)
	}
}

@(test)
wall_blocks_and_changes_nothing :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[6][5] = .Wall
	move_dude(&g, 1, 0)
	testing.expect_value(t, g.column, 5)
	testing.expect_value(t, g.board[5][5], Cell.Dude)
	testing.expect_value(t, g.board[6][5], Cell.Wall)
	testing.expect_value(t, tally(&g)[.Fire], 0)
}

@(test)
leaving_a_cell_leaves_fire :: proc(t: ^testing.T) {
	g := blank_game()
	move_dude(&g, 0, -1)
	testing.expect_value(t, g.row, 4)
	testing.expect_value(t, g.board[5][5], Cell.Fire)
	testing.expect_value(t, g.board[5][4], Cell.Dude)
	testing.expect(t, g.alive)
}

@(test)
gold_scores :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[4][5] = .Gold
	move_dude(&g, -1, 0)
	testing.expect_value(t, g.score, 1)
	testing.expect_value(t, g.left, 15)
	testing.expect_value(t, g.level, 1)
}

@(test)
ice_adds_protection_and_fire_consumes_it :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[6][5] = .Ice
	g.board[7][5] = .Fire
	move_dude(&g, 1, 0)
	testing.expect_value(t, g.protection, 1)
	move_dude(&g, 1, 0)
	testing.expect_value(t, g.protection, 0)
	testing.expect(t, g.alive)
	testing.expect_value(t, g.board[7][5], Cell.Dude)
}

@(test)
fire_without_protection_kills :: proc(t: ^testing.T) {
	g := blank_game()
	g.board[5][6] = .Fire
	move_dude(&g, 0, 1)
	testing.expect(t, !g.alive)
	testing.expect_value(t, g.board[5][6], Cell.Dead_Dude)
	testing.expect_value(t, g.board[5][5], Cell.Fire)
	testing.expect_value(t, g.row, 6)
}

@(test)
last_coin_starts_next_level :: proc(t: ^testing.T) {
	g := blank_game()
	g.left = 1
	g.score = 15
	g.board[5][4] = .Gold
	move_dude(&g, 0, -1)
	testing.expect_value(t, g.level, 2)
	testing.expect_value(t, g.score, 16)
	testing.expect_value(t, g.left, coin_count(2))
	testing.expect_value(t, g.column, 5)
	testing.expect_value(t, g.row, 4)
	testing.expect_value(t, g.board[5][4], Cell.Dude)
	// Quirk kept from the original: the rebuilt board put its dude on the old cell,
	// which then becomes fire like any cell the player leaves.
	testing.expect_value(t, g.board[5][5], Cell.Fire)
	counts := tally(&g)
	testing.expect_value(t, counts[.Dude], 1)
	testing.expect_value(t, counts[.Wall], wall_count(2))
}

@(test)
each_move_has_its_sound :: proc(t: ^testing.T) {
	g := blank_game()
	move_dude(&g, 0, -1)
	testing.expect_value(t, g.sound, Sound.Step)

	g = blank_game()
	g.board[6][5] = .Wall
	move_dude(&g, 1, 0) // blocked: no new sound
	testing.expect_value(t, g.sound, Sound.None)

	g = blank_game()
	g.board[4][5] = .Gold
	move_dude(&g, -1, 0)
	testing.expect_value(t, g.sound, Sound.Coin)

	g = blank_game()
	g.board[6][5] = .Ice
	move_dude(&g, 1, 0)
	testing.expect_value(t, g.sound, Sound.Ice)

	g = blank_game()
	g.protection = 1
	g.board[5][6] = .Fire
	move_dude(&g, 0, 1)
	testing.expect_value(t, g.sound, Sound.Shield)

	g = blank_game()
	g.board[5][6] = .Fire
	move_dude(&g, 0, 1)
	testing.expect_value(t, g.sound, Sound.Death)

	g = blank_game()
	g.left = 1
	g.board[5][4] = .Gold
	move_dude(&g, 0, -1)
	testing.expect_value(t, g.sound, Sound.Level_Up)
}
