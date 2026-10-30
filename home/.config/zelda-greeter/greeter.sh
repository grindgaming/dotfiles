#!/usr/bin/env bash
# Terminal greeter: fastfetch with a looping Triforce GIF as the logo.
# In kitty the terminal keeps playing the GIF on its own after this exits.
# Elsewhere it falls back to the one-off ASCII spin.

dir="$HOME/.config/zelda-greeter"
gif="$dir/logo.gif"
logo_cols=32 logo_rows=13 logo_top=2 logo_left=2  # must match fastfetch-gif.jsonc

if [[ -z $KITTY_WINDOW_ID || ! -f $gif ]] || ! command -v kitten >/dev/null; then
    python3 "$dir/triforce.py" spin
    fastfetch --config "$dir/fastfetch.jsonc"
    exit
fi

# Height of the greeter: the blank logo or the 17 info lines, whichever is taller
lines=$(( logo_rows + logo_top > 17 ? logo_rows + logo_top : 17 ))

# Scroll first so the whole greeter fits on screen, then note where it starts
printf '%*s' "$lines" '' | tr ' ' '\n'
printf '\e[%dA' "$lines"
IFS='[;' read -rs -d R -t 1 -p $'\e[6n' _ row _ </dev/tty

if [[ $row =~ ^[0-9]+$ ]]; then
    # icat leaves the cursor at the image's corner; put it back for fastfetch
    printf '\e7'
    kitten icat --stdin=no --place "${logo_cols}x${logo_rows}@${logo_left}x$((row - 1 + logo_top))" "$gif"
    printf '\e8'
fi
printf "\e[?7l"  # cut off long lines instead of wrapping into the logo
fastfetch --config "$dir/fastfetch-gif.jsonc"
printf "\e[?7h"
