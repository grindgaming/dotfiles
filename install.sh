#!/bin/bash
echo "=== Stelle Arch Linux Setup wieder her ==="

# Temporäre Kopien der Paketlisten anlegen (damit das Original unberührt bleibt)
TMP_ARCH=$(mktemp)
TMP_AUR=$(mktemp)
cp packages-arch.txt "$TMP_ARCH"
cp packages-aur.txt "$TMP_AUR"

echo "--- Hardware-Check ---"

# 1. Abfrage für Apple Silicon
read -p "Installierst du das auf einem Apple Silicon Mac (Asahi Linux)? (y/n): " is_mac
if [[ "$is_mac" =~ ^[YyJj] ]]; then
    echo "-> Apple Silicon Modus aktiv. Filtere inkompatible Pakete (lib32, x86, Nvidia, AMD)..."
    # ARM (Apple Silicon) unterstützt kein multilib (32-bit) und braucht keine Fremd-GPU-Treiber
    sed -i '/^lib32-/d' "$TMP_ARCH"
    sed -i '/^lib32-/d' "$TMP_AUR"
    sed -i '/nvidia/Id' "$TMP_ARCH"
    sed -i '/nvidia/Id' "$TMP_AUR"
    sed -i '/amdgpu/Id' "$TMP_ARCH"
    sed -i '/vulkan-radeon/Id' "$TMP_ARCH"
else
    # 2. Abfrage für Nvidia (nur relevant, wenn es kein Mac ist)
    read -p "Hat dieser Rechner eine Nvidia-Grafikkarte? (y/n): " has_nvidia
    if [[ ! "$has_nvidia" =~ ^[YyJj] ]]; then
        echo "-> Nvidia-frei. Filtere proprietäre Nvidia-Treiber heraus..."
        # Löscht alle Zeilen, die das Wort "nvidia" oder "prime" enthalten
        sed -i '/nvidia/Id' "$TMP_ARCH"
        sed -i '/nvidia/Id' "$TMP_AUR"
        sed -i '/prime/Id' "$TMP_ARCH"
    fi
fi

echo "=== Installiere offizielle Pakete ==="
sudo pacman -S --needed - < "$TMP_ARCH"

echo "=== Installiere AUR Pakete ==="
yay -S --needed - < "$TMP_AUR"

# Temporäre Listen nach der Installation spurlos löschen
rm "$TMP_ARCH" "$TMP_AUR"

echo "=== Kopiere Configs ==="
cp -r .config/* ~/.config/
cp .bashrc ~/

echo "=== System erfolgreich wiederhergestellt! Bitte neu starten. ==="
