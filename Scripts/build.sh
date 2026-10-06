#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
app_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
mkdir -p build
xcodebuild -quiet -project LlamaBar.xcodeproj -scheme LlamaBar \
    -configuration Release -destination 'platform=macOS,arch=x86_64' \
    -derivedDataPath build/DerivedData-LlamaBar build CODE_SIGNING_ALLOWED=NO
# Desktop file providers can reattach FinderInfo after signing. Keep the signed
# development bundle outside that folder and retain a portable archive in the project.
package_dir=$(mktemp -d "/private/tmp/LlamaBar-${app_version}.XXXXXX")
ditto --norsrc --noextattr build/DerivedData-LlamaBar/Build/Products/Release/LlamaBar.app "$package_dir/LlamaBar.app"
xattr -cr "$package_dir/LlamaBar.app"
codesign --force --sign - "$package_dir/LlamaBar.app"
codesign --verify --strict "$package_dir/LlamaBar.app"
archive="build/LlamaBar-${app_version}-macOS-Intel.zip"
ditto -c -k --keepParent --norsrc --noextattr "$package_dir/LlamaBar.app" "$archive"
if [[ -e build/LlamaBar.app || -L build/LlamaBar.app ]]; then
    rm -rf build/LlamaBar.app
fi
ln -s "$package_dir/LlamaBar.app" build/LlamaBar.app
(
    cd build
    LC_ALL=C shasum -a 256 "${archive#build/}" > "${archive#build/}.sha256"
)
printf 'Built LlamaBar %s: %s/build/LlamaBar.app\nArchive: %s/%s\n' "$app_version" "$PWD" "$PWD" "$archive"
