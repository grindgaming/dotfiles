#!/usr/bin/env bash
# Einstiegspunkt auf einer frischen Arch-Installation:
#   sudo pacman -S --needed git
#   git clone https://github.com/grindgaming/dotfiles ~/dotfiles
#   ~/dotfiles/install.sh
# Alle Optionen von "dotfiles restore" werden durchgereicht (z.B. --yes, --mainmod super).

exec "$(dirname "$(readlink -f "$0")")/dotfiles" restore "$@"
