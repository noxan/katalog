#!/bin/bash
# icon.svg -> AppIcon.icns. No third-party rasterizer needed: qlmanage (built
# into macOS) renders the SVG, sips downscales, iconutil packs the .icns.
# Usage: build-icon.sh <icon.svg> <out.icns>
set -euo pipefail

svg="$1"
out="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

qlmanage -t -s 1024 -o "$work" "$svg" >/dev/null 2>&1
master="$work/$(basename "$svg").png"

set="$work/AppIcon.iconset"
mkdir -p "$set"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s"           "$master" --out "$set/icon_${s}x${s}.png"     >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$master" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$set" -o "$out"
echo "Wrote $out"
