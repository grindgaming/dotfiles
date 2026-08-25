#!/bin/bash
echo "=== Installiere Arch Linux Setup ==="

# 1. Installiere alle offiziellen Pakete aus der Textdatei
sudo pacman -S --needed - < packages-arch.txt

# 2. Installiere alle AUR Pakete (mit yay)
yay -S --needed - < packages-aur.txt

# 3. Kopiere die Dotfiles an die richtige Stelle
cp -r .config/* ~/.config/
cp .bashrc ~/

echo "=== Installation abgeschlossen! Bitte neu starten. ==="
