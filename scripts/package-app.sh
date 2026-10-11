#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d dist.noindex/KeyBridge.app ]] || { print -u2 "Build KeyBridge first"; exit 1; }
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/keybridge-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto dist.noindex/KeyBridge.app "$STAGING/KeyBridge.app"
ln -s /Applications "$STAGING/Applications"
cp INSTALL.md "$STAGING/インストール方法.txt"
/usr/bin/hdiutil create -volname KeyBridge -srcfolder "$STAGING" -format UDZO -ov dist/KeyBridge-0.2.1-arm64.dmg
