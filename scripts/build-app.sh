#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build --build-system native -c release
bin_dir="$(swift build --build-system native -c release --show-bin-path)"
app_dir="$project_dir/../NookSweep.app"
resource_dir="$app_dir/Contents/Resources"
iconset_dir="$project_dir/.build/NookSweep.iconset"
mkdir -p "$app_dir/Contents/MacOS" "$resource_dir/assets" "$iconset_dir"
cp "$bin_dir/NookSweep" "$app_dir/Contents/MacOS/NookSweep"
cp "$project_dir/scripts/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/README.md" "$resource_dir/README.md"
cp "$project_dir/assets/NookSweep-logo.png" "$resource_dir/assets/NookSweep-logo.png"
swift "$project_dir/scripts/AppIcon.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$resource_dir/NookSweep.icns"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$project_dir/../NookSweep-app.zip"
printf '已建立：%s\n' "$app_dir"
