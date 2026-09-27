#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
zig build -Doptimize=ReleaseSafe

APP="${1:-/Applications/Scarlett Gain Overlay.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp packaging/macos/Info.plist "$APP/Contents/Info.plist"
cp zig-out/bin/scarlett-gain-overlay "$APP/Contents/MacOS/scarlett-gain-overlay"
codesign --force --sign - "$APP" >/dev/null
printf 'Installed %s\n' "$APP"
