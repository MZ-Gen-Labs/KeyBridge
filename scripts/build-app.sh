#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-icons.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
APP="$PWD/dist.noindex/KeyBridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARY_DIR=$(swift build -c release --show-bin-path)
# Replace the binary inode so macOS does not reuse a cached signature of the previous build.
cp "$BINARY_DIR/KeyBridge" "$APP/Contents/MacOS/.KeyBridge.new"
mv -f "$APP/Contents/MacOS/.KeyBridge.new" "$APP/Contents/MacOS/KeyBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/keybridge_mcp.py "$APP/Contents/Resources/keybridge_mcp.py"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
# A stable identifier allows local Keychain access; no iCloud entitlement is needed.
codesign --force --sign - --identifier dev.keybridge.app "$APP"
print "Built: $APP"

# Keep developer builds out of the Mac application launcher.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$APP"
fi
