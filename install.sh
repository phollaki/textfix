#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

app=/Applications/TextFix.app
agent=~/Library/LaunchAgents/com.akos.textfix.plist
build=$(mktemp -d)

swiftc -O TextFix.swift -o "$build/TextFix"
swift icon.swift "$build/icon.png"
mkdir "$build/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$build/icon.png" --out "$build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$build/icon.png" --out "$build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$build/AppIcon.iconset" -o "$build/AppIcon.icns"

launchctl bootout gui/$(id -u)/com.akos.textfix 2>/dev/null || true
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" ~/.local/bin
cp Info.plist "$app/Contents/"
cp "$build/TextFix" "$app/Contents/MacOS/"
cp "$build/AppIcon.icns" "$app/Contents/Resources/"
codesign --force --sign - "$app"
touch "$app"

ln -sf "$PWD/textfix" ~/.local/bin/textfix
cp com.akos.textfix.plist "$agent"
launchctl bootstrap gui/$(id -u) "$agent"
rm -rf "$build"
echo "TextFix installed. Turn it on in System Settings > Privacy & Security > Accessibility."
