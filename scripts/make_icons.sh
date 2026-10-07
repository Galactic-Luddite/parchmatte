#!/usr/bin/env bash
# Scale Resources/AppIcon-1024.png into the Xcode asset catalog and an .icns
# for the SwiftPM build. Run after scripts/generate_icon.py.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SRC="Resources/AppIcon-1024.png"
SET="Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET" "$ICONSET"

images=""
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        suffix=""; if [ "$scale" = 2 ]; then suffix="@2x"; fi; name="icon_${size}x${size}${suffix}.png"
        sips -z "$px" "$px" "$SRC" --out "$SET/$name" >/dev/null
        cp "$SET/$name" "$ICONSET/$name"
        images="$images{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"${scale}x\",\"filename\":\"$name\"},"
    done
done
printf '{"images":[%s],"info":{"author":"xcode","version":1}}\n' "${images%,}" > "$SET/Contents.json"
printf '{"info":{"author":"xcode","version":1}}\n' > "Resources/Assets.xcassets/Contents.json"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "icons written"
