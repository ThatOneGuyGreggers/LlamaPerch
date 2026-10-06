#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PWD/build/SwiftPM/clang-cache"
mkdir -p build/SwiftPM/cache build/SwiftPM/config build/SwiftPM/security
swift test --disable-sandbox --scratch-path "$PWD/build/SwiftPM" --cache-path "$PWD/build/SwiftPM/cache" \
    --config-path "$PWD/build/SwiftPM/config" --security-path "$PWD/build/SwiftPM/security" \
    -Xswiftc -warnings-as-errors "$@"
