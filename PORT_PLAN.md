# Wandermaze: Odin/WASM port plan

Follows the bok's `Tech/Odin wasm recipe.md` (Murder Hobo / Fortune Hunter "software framebuffer" variant, combined with the Roomba Rights pure-core split) and `Tech/Release standard.md`. Coxswain project: `wandermaze` (tasks 71-78; 75 cancelled).

## Goal
Reproduce the TIC-80 game's behavior (see CLAUDE.md) as Odin compiled to `js_wasm32`, same 240x136 look, same rules and controls. Web-only: the pure core is tested natively with `odin test`; there is no native window.

## Findings that shape the plan
- No palette chunk in the cart: it uses the TIC-80 default palette (Sweetie-16). Hardcode those 16 colors.
- Tiles chunk is 256 bytes = 8 tiles of 4bpp 8x8 (index 0 blank, 1..7 used).
- Sound chunks exist but the code never calls `sfx`/`music`; skip audio. The 16 KB screen chunk is the itch cover image.
- Text uses TIC-80's built-in font via `print`; bake the needed glyphs (letters, digits, `:` `!`) into bit rows.

## Layout
```
src/game/    pure rules + framebuffer + baked assets (no platform imports)
src/web/     #+build js, package main: exported proc "c" functions
web/index.html
tools/       extract_cart.py, build.sh, test.sh, ship.sh
shippit.sh   one-line wrapper for tools/ship.sh
```
Built with `-collection:tggd=src`. Odin: `/home/yermom/ODIN/odin` (dev-2026-07; `~/.local/bin/odin` is the same version).

## Milestones (coxswain ids)
1. **#71 Extract assets**: `tools/extract_cart.py` (stdlib only) parses the cart and writes sprite/palette/font tables into `src/game`. Verify with rendered PNGs; Anvil can hold the canonical sprites.
2. **#72 Game core**: `src/game` port of the Lua, flat POD `Game`, RNG in the struct. Preserve "left cell becomes fire" and the exact effect order in `move_dude` (level-up re-inits the board before the old cell is overwritten).
3. **#73 Tests**: `#+build !js` tests, `odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1`; `tools/test.sh` also runs `odin check` for `js_wasm32` on each package.
4. **#74 Software framebuffer**: 240x136 `u32` RGBA, indexed draw then palette resolve; board at (0,0), HUD at x=136, y = 0,8,24,32,48,56,72,80,96,104.
5. **#76 Web layer**: page owns `requestAnimationFrame`, calls exported `proc "c"` functions, `putImageData` into a canvas with `image-rendering: pixelated` and integer scaling. Read `e.key` before `e.code`. Seed RNG from page entropy (precaution; see Gotchas).
6. **#77 Parity**: run `pub-html/wandermaze.zip` beside the port, compare screenshots and hand-play a level; optional node script comparing native vs wasm frame hashes.
7. **#78 Release tooling**: `tools/build.sh`, `test.sh`, `ship.sh` (push only with `--push`), `shippit.sh` as a wrapper, `ITCH_DESCRIPTION.md`, `assets/cover.png` (630x500), `assets/screenshots/`.

## Rules to honour
- Never `git push`, `butler push` or run a ship script unless the user says so. The existing `shippit.sh` runs `git add -A` and commits: do not run it; replace it in #78.
- The live itch page has channels `linux`, `windows`, `mac`, `html`: do not rename them.
- Do not treat the game's design (the maze closing behind you) as a problem.
- Once ported, add `Games/Wandermaze.md`, a `Home.md` row and a `Steam pivot evaluation.md` row in the bok.

## Open questions
- Restart and quit keys: confirm TIC-80 codes 68/70, pick web bindings (quit likely dropped).
- Should the port keep the desktop builds (would need a native client) or replace only the html channel?
