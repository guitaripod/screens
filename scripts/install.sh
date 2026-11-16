#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product screens
products="$(swift build -c release --show-bin-path)"

bin="$HOME/.local/bin"
install -d "$bin"
install -m 755 "$products/screens" "$bin/screens.new"
mv -f "$bin/screens.new" "$bin/screens"

rm -rf .build
"$bin/screens" --version
