#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
binaries=()
for architecture in arm64 x86_64; do
    build_args=(--build-system native -c release --triple "${architecture}-apple-macosx14.0")
    swift build "${build_args[@]}"
    bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
    binaries+=("$bin_dir/NookSweep")
done
app_dir="$project_dir/../NookSweep.app"
resource_dir="$app_dir/Contents/Resources"
iconset_dir="$project_dir/.build/NookSweep.iconset"
mkdir -p "$app_dir/Contents/MacOS" "$resource_dir/assets" "$iconset_dir"
xcrun lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/NookSweep"
for architecture in arm64 x86_64; do
    xcrun lipo "$app_dir/Contents/MacOS/NookSweep" -verify_arch "$architecture"
done
cp "$project_dir/scripts/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/README.md" "$resource_dir/README.md"
cp "$project_dir/assets/NookSweep-logo.png" "$resource_dir/assets/NookSweep-logo.png"
swift "$project_dir/scripts/AppIcon.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$resource_dir/NookSweep.icns"
codesign --force --sign - "$app_dir"
codesign --verify --strict --all-architectures "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$project_dir/../NookSweep-app.zip"
printf '已建立：%s\n' "$app_dir"
