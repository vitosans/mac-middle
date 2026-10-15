#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
tag="${1:-v$version}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$tag" != "v$version" ]; then
    printf 'Release tag must match Info.plist version: v%s\n' "$version" >&2
    exit 1
fi
swift test
bash scripts/build.sh --universal
app_dir="$project_dir/build/Mac Middle.app"
plutil -lint Info.plist "$app_dir/Contents/Info.plist"
xcrun lipo "$app_dir/Contents/MacOS/MacMiddle" -verify_arch arm64
xcrun lipo "$app_dir/Contents/MacOS/MacMiddle" -verify_arch x86_64
codesign --verify --strict --verbose=2 "$app_dir"
release_dir="$project_dir/build/release"
mkdir -p "$release_dir"
archive="Mac-Middle-$tag-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/$archive"
cd "$release_dir"
shasum -a 256 "$archive" > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
cat > release-notes.md <<EOF
Download **$archive**, unzip it, move **Mac Middle.app** to **Applications**, and enable it under **System Settings → Privacy & Security → Accessibility**.

Requires macOS 13 or later. Includes Apple silicon and Intel builds. The app is ad-hoc signed and is not notarized by Apple. See the [README](https://github.com/vitosans/mac-middle#readme) for first-launch security prompts, setup, and limitations.

Automated checks cover unit tests, universal compilation, bundle metadata, and code signatures. They do not verify live mouse input, real Accessibility responses, or Intel runtime behavior. SHA256SUMS.txt contains the download checksum.
EOF
printf 'Release files prepared in %s\n' "$release_dir"
