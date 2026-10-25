#!/usr/bin/env python3
"""Compare the port's renderer with ss/cover.png, a real screenshot of the original.

The cover shows the 240x136 screen at 2.625x (630 wide), letterboxed to 500 high.
Sample it at the centre of every screen pixel, then check
  1. every 8x8 board block is exactly one of the cart's sprites (sprites + palette parity),
  2. the HUD region matches a frame dumped by the port (text, spacing, colours).
Usage: python3 tools/parity_cover.py FRAME.ppm   (from: odin test src/game ... -define:DUMP_FRAME=FRAME.ppm)
The cover predates the Level line, so HUD rows from y=96 down are skipped.
"""
import os, re, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
assets = open(os.path.join(ROOT, "src/game/assets.odin")).read()
palette = [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in re.findall(r"0x([0-9a-f]{6}),", assets)][:16]
sprites = [list(map(int, m.split(","))) for m in re.findall(r"\t\{((?:\d+, ){63}\d+)\},", assets)]

cover = Image.open(os.path.join(ROOT, "ss/cover.png")).convert("RGB")
scale = 630 / 240
top = (500 - 136 * scale) / 2

def nearest(rgb):
    d = [sum((a - b) ** 2 for a, b in zip(rgb, p)) for p in palette]
    return d.index(min(d)), min(d)

cov = [[None] * 240 for _ in range(136)]
worst = 0
for y in range(136):
    for x in range(240):
        rgb = cover.getpixel((int((x + 0.5) * scale), int(top + (y + 0.5) * scale)))
        cov[y][x], d = nearest(rgb)
        worst = max(worst, d)
print("cover sampled; worst colour distance^2 to a palette entry:", worst)

# 1. board blocks
bad = 0
counts = {}
for c in range(17):
    for r in range(17):
        block = [cov[r * 8 + py][c * 8 + px] for py in range(8) for px in range(8)]
        hits = [i for i, s in enumerate(sprites) if s == block]
        if hits:
            counts[hits[0]] = counts.get(hits[0], 0) + 1
        else:
            bad += 1
print("board blocks: %d of 289 match a sprite exactly, %d do not; per sprite %s" % (289 - bad, bad, dict(sorted(counts.items()))))

# 2. HUD
data = open(sys.argv[1], "rb").read()
h = data.index(b"255\n") + 4
px = data[h:]
mine = [[min(range(16), key=lambda i: sum((a - b) ** 2 for a, b in zip(palette[i], px[(y * 240 + x) * 3:(y * 240 + x) * 3 + 3])))
         for x in range(240)] for y in range(136)]
diff = [(x, y) for y in range(96) for x in range(136, 240) if mine[y][x] != cov[y][x]]
print("HUD x>=136, y<96: %d of %d pixels differ" % (len(diff), 104 * 96))
if diff:
    print("first differences:", diff[:10])
sys.exit(1 if bad or diff else 0)
