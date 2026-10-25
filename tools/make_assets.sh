#!/usr/bin/env bash
# Regenerates assets/cover.png (630x500) and assets/screenshots/ from the real renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -o:speed \
	-define:DUMP_FRAME="$T/play.ppm" -define:DUMP_FRAME_DEAD="$T/dead.ppm" -define:DUMP_FRAME_TITLE="$T/title.ppm" >/dev/null
mkdir -p assets/screenshots
python3 -I tools/make_assets.py "$T/play.ppm" "$T/dead.ppm" "$T/title.ppm"
