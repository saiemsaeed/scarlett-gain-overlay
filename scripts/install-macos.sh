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

AGENT="$HOME/Library/LaunchAgents/dev.saiem.scarlett-gain-overlay.plist"
mkdir -p "$(dirname "$AGENT")"
cp packaging/macos/dev.saiem.scarlett-gain-overlay.plist "$AGENT"
launchctl bootout "gui/$(id -u)/dev.saiem.scarlett-gain-overlay" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"

printf 'Installed %s and enabled launch at login\n' "$APP"
