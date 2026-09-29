#!/bin/sh
set -eu

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl eval 'hl.window_rule({name="scarlett-gain-overlay-bottom", match={class="Scarlett Gain"}, float=true, size={174,88}, move={"(monitor_w-window_w)*0.5","monitor_h-window_h-42"}, pin=true, no_initial_focus=true, no_focus=true, no_anim=true, border_size=0, no_shadow=true})' >/dev/null
fi

cd "$(dirname "$0")/.."
exec ./zig-out/bin/scarlett-gain-overlay "$@"
