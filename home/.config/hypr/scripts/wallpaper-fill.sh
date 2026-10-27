#!/usr/bin/env bash
# Sets the current wallpaper on every output that awww shows without an image
# (e.g. a monitor plugged in after login).
CACHE_FILE="$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper"
[ -f "$CACHE_FILE" ] || exit 0
WALLPAPER="$(cat "$CACHE_FILE")"

until awww query >/dev/null 2>&1; do sleep 0.5; done

awww query | grep -v "image:" | sed -E 's/^: ([^:]+):.*/\1/' | while read -r output; do
    [ -n "$output" ] && awww img "$WALLPAPER" -o "$output"
done
