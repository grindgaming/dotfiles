#!/usr/bin/env bash
# Plays a video as live wallpaper (mpvpaper) on every monitor.
# Runs above the awww wallpaper (layer "bottom"), so the ML4W colors keep
# coming from the awww image. Pauses while a fullscreen window hides it.
VIDEO="${1:-$HOME/.config/ml4w/wallpapers/zelda-botw.mp4}"

command -v mpvpaper >/dev/null && [ -f "$VIDEO" ] || exit 0

pkill -x mpvpaper 2>/dev/null
sleep 0.5

# With the NVIDIA dGPU switched off (see hypr/custom.lua), an empty
# CUDA_VISIBLE_DEVICES stops libcuda from opening and waking it;
# video decoding stays on the iGPU.
if [ "$(cat "$HOME/.config/ml4w/settings/nvidia-dgpu" 2>/dev/null)" = off ]; then
    export CUDA_VISIBLE_DEVICES=
fi

exec mpvpaper -p -a FULL -l bottom \
    -o "no-audio loop hwdec=vaapi profile=fast msg-level=all=warn term-status-msg=" \
    ALL "$VIDEO" > "$HOME/.cache/live-wallpaper.log" 2>&1
