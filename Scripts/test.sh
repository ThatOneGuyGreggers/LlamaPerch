#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security
swift test --disable-sandbox --cache-path "$PWD/.build/swiftpm-cache" \
    --config-path "$PWD/.build/swiftpm-config" --security-path "$PWD/.build/swiftpm-security" \
    -Xswiftc -warnings-as-errors "$@"
