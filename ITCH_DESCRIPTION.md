# Itch.io page text

Page: https://thegrumpygamedev.itch.io/wandermaze
Pasted in by hand; nothing here is published by the repo.

## Short description

Collect the gold, grab the ice, and don't step on fire. Every square you leave behind turns to fire.

## Paste this as the page description

The maze closes behind you.

You are the little green fellow on a 17 by 17 board. Walk onto **gold** to score. Collect all 16 coins to clear the level and get a bigger, hotter board. **Ice** gives you protection, and each point of protection lets you survive one step onto **fire**. Walls block your way.

Here is the catch: **every square you leave turns into fire**, so there is no going back the way you came.

**Controls:** arrow keys to move one step at a time. When you die, press F2 (or Enter, Space or R) to play again. On a phone or tablet, swipe to move and tap to restart.

**Made with:** the original was made in TIC-80. This version is a port to Odin, compiled to WebAssembly and drawn to a plain 2D canvas, with the original game's sprites and rules kept as they were. The port was made with Claude (generative AI) working alongside TheGrumpyGameDev.

## Notes (not for the page)

- Push target: `thegrumpygamedev/wandermaze:html`. `shippit.sh` wraps `tools/ship.sh`, which tests, builds with `-o:size` and zips; it only pushes with `--push`. That replaces the html channel's old TIC-80 export. The linux, windows and mac channels are the original TIC-80 builds and are not touched.
- **The live page is tagged "No generative AI was used."** The port was written with Claude, so that tag and the disclosure line above need your decision before the port goes live. Nothing here changes the page.
- On the Edit game screen: "Kind of project" HTML, "This file will be played in the browser" ticked, and an embed of 720 by 408 (the game is 240 by 136 and scales to fit).
- The cover is `assets/cover.png` (630 by 500) and the screenshots are `assets/screenshots/`, both made by `tools/make_assets.sh` from the real renderer.
- Known behaviour difference: the original hangs forever when the board fills up (level 15); the port keeps playing with a fuller board.
