#!/usr/bin/env bash
# Plays a Wallpaper Engine wallpaper (linux-wallpaperengine) on every monitor.
# Runs above the awww wallpaper (layer "bottom"), so the ML4W colors keep
# coming from the awww image.
# Needs Steam with Wallpaper Engine (app 431960) and the subscribed workshop item.
WALLPAPER_ID="${1:-2236794660}"

command -v linux-wallpaperengine >/dev/null || exit 0

pkill -x linux-wallpaper 2>/dev/null  # process name, truncated to 15 chars
sleep 0.5

args=()
for output in $(hyprctl monitors -j | jq -r '.[].name'); do
    args+=(--screen-root "$output" --bg "$WALLPAPER_ID")
done
[ ${#args[@]} -gt 0 ] || exit 0

# Empty CUDA_VISIBLE_DEVICES stops libcuda from opening the NVIDIA dGPU
# (keeps it asleep, see hypr/custom.lua); video decoding stays on the iGPU.
CUDA_VISIBLE_DEVICES= exec linux-wallpaperengine --silent --fps 30 "${args[@]}" \
    > "$HOME/.cache/linux-wallpaperengine.log" 2>&1
