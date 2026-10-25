#!/usr/bin/env python3
"""Cover and screenshots from frames dumped by tools/make_assets.sh (Pillow)."""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load(path):
    return Image.open(path).convert("RGB")

play, dead = load(sys.argv[1]), load(sys.argv[2])
# Cover: the 240x136 screen at the same 2.625x as the original cover, letterboxed to 630x500.
cover = Image.new("RGB", (630, 500), (0, 0, 0))
cover.paste(play.resize((630, 357), Image.NEAREST), (0, (500 - 357) // 2))
cover.save(os.path.join(ROOT, "assets", "cover.png"))
# Screenshots: whole-number 3x so the pixels stay crisp.
play.resize((720, 408), Image.NEAREST).save(os.path.join(ROOT, "assets", "screenshots", "01-play.png"))
dead.resize((720, 408), Image.NEAREST).save(os.path.join(ROOT, "assets", "screenshots", "02-dead.png"))
print("wrote assets/cover.png and assets/screenshots/")
