#!/usr/bin/env bash
# Snipping-tool style: freeze screen, drag a region, copy PNG to clipboard.

# Freeze the screen so the selection matches what you saw
hyprpicker -r -z >/dev/null 2>&1 &
picker=$!
sleep 0.1

geom=$(slurp -d)
status=$?

# Esc / right-click cancels
if [[ $status -ne 0 || -z "$geom" ]]; then
    kill "$picker" 2>/dev/null
    exit 0
fi

# Capture while still frozen, then unfreeze
grim -g "$geom" - | wl-copy --type image/png
kill "$picker" 2>/dev/null
notify-send -a Screenshot -t 2000 "Screenshot copied" "Region copied to clipboard"
