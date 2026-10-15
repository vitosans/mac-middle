#!/bin/bash
set -euo pipefail
case "${1:-}" in
    "") architectures=("$(uname -m)") ;;
    --universal) architectures=(arm64 x86_64) ;;
    *) printf 'Usage: %s [--universal]\n' "$0" >&2; exit 1 ;;
esac
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/Mac Middle.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
icon_work_dir="$(mktemp -d "$project_dir/build/icon.XXXXXX")"
trap 'rm -rf "$icon_work_dir"' EXIT
iconset_dir="$icon_work_dir/MacMiddle.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/mac-middle.png" \
        --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$project_dir/mac-middle.png" \
        --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/MacMiddle.icns"
binaries=()
for architecture in "${architectures[@]}"; do
    binary="$icon_work_dir/MacMiddle-$architecture"
    xcrun swiftc -O -target "$architecture-apple-macosx13.0" \
        "$project_dir/Sources/main.swift" "$project_dir/Sources/WindowInteraction.swift" \
        -o "$binary"
    binaries+=("$binary")
done
if [ "${#binaries[@]}" -eq 1 ]; then
    cp "${binaries[0]}" "$app_dir/Contents/MacOS/MacMiddle"
else
    xcrun lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/MacMiddle"
fi
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
