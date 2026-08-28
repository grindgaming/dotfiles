#!/bin/bash
echo "=== Stelle Arch Linux Setup wieder her ==="

# Temporäre Kopien der Paketlisten anlegen
TMP_ARCH=$(mktemp)
TMP_AUR=$(mktemp)
cp packages-arch.txt "$TMP_ARCH"
cp packages-aur.txt "$TMP_AUR"

echo "--- Hardware-Check ---"

# 1. Abfrage für Apple Silicon
read -p "Installierst du das auf einem Apple Silicon Mac (Asahi Linux)? (y/n): " is_mac
if [[ "$is_mac" =~ ^[YyJj] ]]; then
    echo "-> Apple Silicon Modus aktiv. Filtere inkompatible Pakete..."
    sed -i '/^lib32-/d' "$TMP_ARCH"
    sed -i '/^lib32-/d' "$TMP_AUR"
    sed -i '/nvidia/Id' "$TMP_ARCH"
    sed -i '/nvidia/Id' "$TMP_AUR"
    sed -i '/amdgpu/Id' "$TMP_ARCH"
    sed -i '/vulkan-radeon/Id' "$TMP_ARCH"
else
    # 2. Abfrage für Nvidia
    read -p "Hat dieser Rechner eine Nvidia-Grafikkarte? (y/n): " has_nvidia
    if [[ ! "$has_nvidia" =~ ^[YyJj] ]]; then
        echo "-> Nvidia-frei. Filtere proprietäre Nvidia-Treiber heraus..."
        sed -i '/nvidia/Id' "$TMP_ARCH"
        sed -i '/nvidia/Id' "$TMP_AUR"
        sed -i '/prime/Id' "$TMP_ARCH"
    fi
fi

echo "=== Installiere offizielle Pakete ==="
sudo pacman -S --needed - < "$TMP_ARCH"

echo "=== Installiere AUR Pakete ==="
yay -S --needed - < "$TMP_AUR"

rm "$TMP_ARCH" "$TMP_AUR"

echo "=== Kopiere Configs ==="
cp -r .config/* ~/.config/
cp .bashrc ~/

# --- NEU: MainMod Abfrage ---
echo ""
echo "=== Tastatur-Setup (MainMod) ==="
echo "Welche Taste möchtest du als Haupt-Modifikator (mainMod) nutzen?"
echo "1) Alt-Taste (alt)"
echo "2) Windows-Taste (super)"
echo "3) Command-Taste (cmd - für Macs)"
read -p "Bitte wähle (1, 2 oder 3): " mod_choice

case $mod_choice in
    2) 
        VARIANT="superMainMod.lua" 
        echo "-> Windows-Taste (super) ausgewählt."
        ;;
    3) 
        VARIANT="cmdMainMod.lua" 
        echo "-> Command-Taste (cmd) ausgewählt."
        ;;
    *) 
        VARIANT="altMainMod.lua" 
        echo "-> Alt-Taste (alt) ausgewählt (Standard)."
        ;;
esac

# Zieldatei mit der ausgewählten Variante überschreiben
cat <<EOF > ~/.config/hypr/conf/keybinding.lua
local name = "$VARIANT"
load_variant(name,"keybindings")
EOF
# ------------------------------

echo ""
echo "=== System erfolgreich wiederhergestellt! Bitte neu starten. ==="
