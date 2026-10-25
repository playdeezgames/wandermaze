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
  - `python3 -I tools/extract_assets.py [--png out.png]` (needs Pillow) regenerates `src/game/assets.odin` (do not hand-edit) from the vendored Urizen sheet in `tools/data/`; the hand-drawn flame and droplet live in that script.
  - Frame dump / marketing images: `tools/make_assets.sh` renders seeded frames with the real renderer (`-define:DUMP_FRAME=a.ppm -define:DUMP_FRAME_DEAD=b.ppm` on `odin test`) and writes `assets/cover.png` and `assets/screenshots/`.
- (Historical, the original cartridge) The code chunk can be extracted from the cart without TIC-80. `.tic` is a sequence of chunks, each `[type(low 5 bits)|bank(high 3 bits)][size u16 LE][reserved byte][data]`; type 5 is the Lua code, type 1 is tiles (sprites), others are palette/map/etc. Parse with a few lines of Python (`python3 -I`).

## Game design (as recovered from the cart code)

The whole game is ~230 lines of Lua in a single code chunk:

- 17x17 grid, one 8x8 sprite per cell (sprite index == cell type, 1..7: empty, fire, dude, ice, gold, wall, dead dude); the HUD is drawn as text at x=136 beside the 136x136 board.
- Cell state lives in `board[col][row]`; player position and stats in the `game` table (`score`, `alive`, `protection`, `level`, `moves`, `left`, `column`, `row`).
- Per level (`l`): 16 coins, `32+16*(l-1)` fire, `max(1, 4-(l-1)//2)` ice, `4+2*(l-1)` walls, placed at random empty cells (rejection sampling in `place`). Collecting all coins increments the level and regenerates the board; the player stays in place.
- Movement (`moveDude`): arrow keys, one step per key press, out-of-bounds and walls block. Gold: +1 score. Ice: +1 protection. Fire: consumes 1 protection, or kills if none. **The cell the player leaves always becomes fire**, which is the core mechanic (the maze closes behind you). Dead state shows a dead sprite; F2 (key 68) restarts and F4 (key 70) calls `exit()` (TIC-80 `keyp` codes: 58-61 up/down/left/right; `keyp` with no hold/period is edge-only, no auto-repeat).
- `poke(0x3ffb,0)` hides the mouse cursor. `game.moves` is initialized but never updated.
- The original cart's sprites (8x8, Sweetie-16) and its use of TIC-80's built-in font are no longer used. The port (October 25, 2026) redraws everything with Urizen tiles; `ss/cover.png` is a stale screenshot of the original (older dude smile, no Level line), and the shipped `pub-html` cart is byte-identical to `wandermaze.tic`.

## Graphics (port)

The port no longer matches the original's look on purpose. The screen is 340x204: a 17x17 board of 12 px icons (204x204, checkered dark floor, the player's square lighter) and a stats panel (level, ALIVE/DEAD, coins left, score, protection, with icons). Icons are single-colour masks from the Urizen 1-bit tileset by vurmux (CC0; credit it in any release): person (104,0), skeleton (104,10) for the dead player, coin (8,20), boulder (6,2), star (33,25), recoloured in `tools/extract_assets.py` (red fire, blue droplet, gray boulder, yellow coin). Urizen has no plain flame or droplet, so those two are hand-drawn 12x12 two-colour masks in the same script. Text is the Urizen bitmap font (sheet row 44-47 from column 78) drawn proportionally, with its decorative letters-only font (rows 47-49) for the title and GAME OVER, both with an integer `scale`. HUD layout is in `draw_game` in `render.odin`. Fire flickers: four hand-drawn flame frames (`Fire`, `Fire_1..3`), and a visual-only `Animation` (own RNG, per-square timers of 70 to 220 ms, random next frame) that `platform_frame(dt)` steps every animation frame; it only asks for a redraw when a square that is on fire changed, and `draw_game` shows the calm frame when no animation is passed.

## Screens

`Game.phase` is `Title` -> `Playing` -> `Level_Complete` -> `Playing` ... -> `Game_Over` (`begin`, last coin or death in `move_dude`, `proceed`, `restart`). The between-levels screen shows what carries over (score, protection) and the next board's counts; the next board is already dealt when it appears, and the last-coin quirk (old cell turns to fire, dude lands on the new board) still applies underneath. `init_game` deals a board and sets `Playing`; the page sets `Title` afterwards, so the board is already dealt behind the title screen. `move_dude` only acts while `Playing`. `restart` and `proceed` are refused until `GAME_OVER_DELAY` (0.8 s) / `LEVEL_COMPLETE_DELAY` (0.6 s) after the screen appears so a key still being mashed cannot skip it; `tick(dt)` advances `phase_time` and reports when `input_ready` turns true (the prompt then appears). Any command continues from the between-levels screen; only restart works on game over. QA: open the page with `?qa` and call `window.__wandermaze.qa_clear_level()` to reach the between-levels screen through the real rules. `draw_game` draws the title screen (decorative Urizen font at 3x, flickering flames, legend, blinking prompt) or the board plus stats panel, with a GAME OVER box over the half of the board that does not hide the skeleton. Prompts blink via `Animation.blink`; `step_animation` only asks for redraws off the playing screen for that.

## Port architecture

`src/game` is pure (rules in `game.odin`, software framebuffer and Urizen-font text in `render.odin`, generated `assets.odin`) and is imported as `tggd:game` via `-collection:tggd=src`. `src/web` (`#+build js`) only exports `proc "c"` functions; `web/index.html` owns `requestAnimationFrame`, input and `putImageData`. The core is deliberately faithful to the Lua quirks (see notes on coxswain task 72); the one deliberate deviation is that `place` stops instead of hanging when the board is full (level 15).

## Sound

The original is silent; the port adds six effects. `move_dude` sets `Game.sound` (`Sound` enum, one per move); `web/index.html` reads it through `platform_take_sound` after each command and plays the matching WAV (`SOUND_FILES` order must match the enum). The WAVs in `assets/sfx/` are exported from the Anvil world `assets/wandermaze.world.json` (PLAY text, square wave); `tools/build.sh` copies them into `build/web/sfx`. M mutes.

## Porting notes

TIC-80 gives a fixed 240x136 screen, 16-color palette, `spr`/`print`/`keyp` APIs and a 60 Hz `TIC()` callback. A port needs to supply equivalents for those (a 240x136 canvas scaled up, the cart's palette and tile bitmaps, a bitmap font for `print`, key-press edge detection) and reproduce the logic above. `math.random` seeding behaviour does not need to match.
