#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcodebuild -quiet -project LlamaMenuBar.xcodeproj -scheme LlamaMenuBar \
    -configuration Release -destination 'platform=macOS,arch=x86_64' \
    -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
# Desktop file providers can reattach FinderInfo after signing. Keep the signed
# development bundle outside that folder and retain a portable archive in the project.
package_dir=$(mktemp -d /private/tmp/LlamaMenuBar-0.0.2.XXXXXX)
ditto --norsrc --noextattr build/DerivedData/Build/Products/Release/LlamaMenuBar.app "$package_dir/LlamaMenuBar.app"
xattr -cr "$package_dir/LlamaMenuBar.app"
codesign --force --sign - "$package_dir/LlamaMenuBar.app"
codesign --verify --strict "$package_dir/LlamaMenuBar.app"
ditto -c -k --keepParent --norsrc --noextattr "$package_dir/LlamaMenuBar.app" build/LlamaMenuBar-0.0.2.zip
if [[ -e build/LlamaMenuBar.app || -L build/LlamaMenuBar.app ]]; then
    rm -rf build/LlamaMenuBar.app
fi
ln -s "$package_dir/LlamaMenuBar.app" build/LlamaMenuBar.app
printf 'Built version 0.0.2: %s/build/LlamaMenuBar.app\nArchive: %s/build/LlamaMenuBar-0.0.2.zip\n' "$PWD" "$PWD"
