# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Wandermaze (https://thegrumpygamedev.itch.io/wandermaze) is a small Lua game written in TIC-80 and shipped to itch.io. The goal of working here is to **reverse engineer it and port it to the Odin/WASM stack**. The original game has no source tree: the whole game is the single cartridge `wandermaze.tic` (~19 KB). Everything in `pub-*/` and `old/` is a build artifact of that cartridge (platform exports with the TIC-80 runtime embedded) and is not source.

Project tooling: task management via the `coxswain` MCP (register as agent name `wandermaze`); game-data structuring (sprites, palette, maps, sounds) via the `anvil-prod` MCP.

## Tooling and commands

- `launch.sh` opens the cart in the TIC-80 IDE. `shippit.sh` exports linux/win/mac/html builds, `butler push`es them to itch (`thegrumpygamedev/wandermaze`), then commits. Both hardcode `IDE=/E/tic80-v1.1-win/tic80` (a Windows path from the author's machine); adjust it before running. Don't run `shippit.sh` without being asked: it publishes and commits.
- Port (Odin, `js_wasm32`; plan in `PORT_PLAN.md`, tasks in coxswain project `wandermaze`, follows the bok's `Tech/Odin wasm recipe.md`):
  - `tools/test.sh`: native `odin test src/game` (single test: add `-define:ODIN_TEST_NAMES=game.<test_name>`), plus `odin check` of both packages for `js_wasm32`.
  - `tools/build.sh [--size]`: builds `build/web` (git-ignored); serve it with `python3 -m http.server -d build/web`.
  - `python3 -I tools/extract_cart.py [--png out.png]` regenerates `src/game/assets.odin` (do not hand-edit) from the cart plus `tools/data/font.inl`.
  - Frame dump: `odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -define:DUMP_FRAME=out.ppm`; `python3 -I tools/parity_cover.py out.ppm` compares it with `ss/cover.png`.
- The code chunk can be extracted from the cart without TIC-80. `.tic` is a sequence of chunks, each `[type(low 5 bits)|bank(high 3 bits)][size u16 LE][reserved byte][data]`; type 5 is the Lua code, type 1 is tiles (sprites), others are palette/map/etc. Parse with a few lines of Python (`python3 -I`).

## Game design (as recovered from the cart code)

The whole game is ~230 lines of Lua in a single code chunk:

- 17x17 grid, one 8x8 sprite per cell (sprite index == cell type, 1..7: empty, fire, dude, ice, gold, wall, dead dude); the HUD is drawn as text at x=136 beside the 136x136 board.
- Cell state lives in `board[col][row]`; player position and stats in the `game` table (`score`, `alive`, `protection`, `level`, `moves`, `left`, `column`, `row`).
- Per level (`l`): 16 coins, `32+16*(l-1)` fire, `max(1, 4-(l-1)//2)` ice, `4+2*(l-1)` walls, placed at random empty cells (rejection sampling in `place`). Collecting all coins increments the level and regenerates the board; the player stays in place.
- Movement (`moveDude`): arrow keys, one step per key press, out-of-bounds and walls block. Gold: +1 score. Ice: +1 protection. Fire: consumes 1 protection, or kills if none. **The cell the player leaves always becomes fire**, which is the core mechanic (the maze closes behind you). Dead state shows a dead sprite; F2 (key 68) restarts and F4 (key 70) calls `exit()` (TIC-80 `keyp` codes: 58-61 up/down/left/right; `keyp` with no hold/period is edge-only, no auto-repeat).
- `poke(0x3ffb,0)` hides the mouse cursor. `game.moves` is initialized but never updated.
- Sprites live in the cart's tiles chunk; there is no palette chunk (default Sweetie-16), the font is TIC-80's built-in (not in the cart), and the sound/music chunks are never used by the code. `print` uses default colour 15, so the HUD is dark slate on near-black, as in the original. `ss/cover.png` is a stale screenshot (older dude smile, no Level line); the shipped `pub-html` cart is byte-identical to `wandermaze.tic`.

## Port architecture

`src/game` is pure (rules in `game.odin`, software framebuffer and TIC-80-style proportional text in `render.odin`, generated `assets.odin`) and is imported as `tggd:game` via `-collection:tggd=src`. `src/web` (`#+build js`) only exports `proc "c"` functions; `web/index.html` owns `requestAnimationFrame`, input and `putImageData`. The core is deliberately faithful to the Lua quirks (see notes on coxswain task 72); the one deliberate deviation is that `place` stops instead of hanging when the board is full (level 15).

## Porting notes

TIC-80 gives a fixed 240x136 screen, 16-color palette, `spr`/`print`/`keyp` APIs and a 60 Hz `TIC()` callback. A port needs to supply equivalents for those (a 240x136 canvas scaled up, the cart's palette and tile bitmaps, a bitmap font for `print`, key-press edge detection) and reproduce the logic above. `math.random` seeding behaviour does not need to match.
