#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
testing_plugin="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
args=(--build-system native --enable-swift-testing --disable-xctest)

# Command Line Tools 6.4 需要明確指定內附的 Swift Testing 與巨集位置。
if [[ -d "$framework_dir/Testing.framework" ]]; then
    args+=(-Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir")
fi
if [[ -f "$testing_plugin" ]]; then
    args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test "${args[@]}" "$@"
