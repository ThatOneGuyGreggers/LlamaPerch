#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ "${1:-}" == "--check" ]]; then
    xcrun swift-format lint --strict --recursive Sources Tests Package.swift
else
    xcrun swift-format format --in-place --recursive Sources Tests Package.swift
fi
