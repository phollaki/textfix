#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcodebuild -project TextFix.xcodeproj -scheme TextFix -configuration Release -derivedDataPath "$work/derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet build

mkdir "$work/dmg"
cp -R "$work/derived/Build/Products/Release/TextFix.app" "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
mkdir -p build
hdiutil create -volname TextFix -srcfolder "$work/dmg" -format UDZO -ov build/TextFix.dmg >/dev/null
echo "app/build/TextFix.dmg"
