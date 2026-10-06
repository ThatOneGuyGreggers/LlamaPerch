#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
app_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
mkdir -p build
xcodebuild -quiet -project LlamaPerch.xcodeproj -scheme LlamaPerch \
    -configuration Release -destination 'platform=macOS,arch=x86_64' \
    -derivedDataPath build/DerivedData-LlamaPerch build CODE_SIGNING_ALLOWED=NO
# Desktop file providers can reattach FinderInfo after signing. Keep the signed
# development bundle outside that folder and retain a portable archive in the project.
package_dir=$(mktemp -d "/private/tmp/LlamaPerch-${app_version}.XXXXXX")
ditto --norsrc --noextattr build/DerivedData-LlamaPerch/Build/Products/Release/LlamaPerch.app "$package_dir/LlamaPerch.app"
xattr -cr "$package_dir/LlamaPerch.app"
codesign --force --sign - "$package_dir/LlamaPerch.app"
codesign --verify --strict "$package_dir/LlamaPerch.app"
archive="build/LlamaPerch-${app_version}-macOS-Intel.zip"
ditto -c -k --keepParent --norsrc --noextattr "$package_dir/LlamaPerch.app" "$archive"
if [[ -e build/LlamaPerch.app || -L build/LlamaPerch.app ]]; then
    rm -rf build/LlamaPerch.app
fi
ln -s "$package_dir/LlamaPerch.app" build/LlamaPerch.app
(
    cd build
    LC_ALL=C shasum -a 256 "${archive#build/}" > "${archive#build/}.sha256"
)
printf 'Built LlamaPerch %s: %s/build/LlamaPerch.app\nArchive: %s/%s\n' "$app_version" "$PWD" "$PWD" "$archive"
