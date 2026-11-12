#!/usr/bin/env bash
# Builds the GitHub Pages copy of the game into docs/ (served from main /docs). Never commits or pushes.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/build.sh --size
rm -rf docs
mkdir docs
cp -r build/web/. docs/
touch docs/.nojekyll
echo "docs/ ready: commit it and push to update https://playdeezgames.github.io/wandermaze/"
