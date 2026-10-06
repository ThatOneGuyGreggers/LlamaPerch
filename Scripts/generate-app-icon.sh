#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build .build/clang-cache Resources/Icons
xcrun swiftc -target x86_64-apple-macos13.0 -swift-version 5 -warnings-as-errors \
    -module-cache-path .build/clang-cache Sources/LlamaPerch/LlamaPerchIcon.swift \
    Scripts/generate-app-icon.swift -o build/GenerateAppIcon
build/GenerateAppIcon "$PWD/Resources/Icons"
iconutil --convert icns Resources/Icons/AppIcon.iconset --output Resources/Icons/AppIcon.icns
