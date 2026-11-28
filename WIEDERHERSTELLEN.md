# Wiederherstellen auf einer frischen Arch-Installation

Voraussetzung: Arch installiert (z.B. `archinstall`), neu gestartet, USB-Stick ab.
Repo ist öffentlich, Klonen ohne GitHub-Login.

## 1. Anmelden

Als **normaler Benutzer**, nicht `root` (sonst startet das Skript nicht).

Kein Benutzer angelegt? Als `root`:

```bash
useradd -m -G wheel BENUTZERNAME
passwd BENUTZERNAME
EDITOR=nano visudo     # "# %wheel ALL=(ALL:ALL) ALL" → # entfernen, speichern
exit
```

## 2. Deutsche Tastatur

```bash
sudo loadkeys de       # entfällt, wenn in archinstall "de" gewählt
```

Mac-Tastatur (kein AltGr): **rechte Option-Taste** wirkt als AltGr.

| Zeichen | Tasten |
|---|---|
| `~` | rechte Option + `+` (rechts neben Ü) |
| `\|` | rechte Option + `<` |
| `@` | rechte Option + `Q` |
| `~` geht gar nicht | `$HOME` statt `~` schreiben |

## 3. Internet

```bash
ping -c 3 archlinux.org
```

| Wenn | Dann |
|---|---|
| Ping klappt | weiter mit 4 |
| LAN-Kabel steckt, kein Internet | [Kein Internet trotz Kabel](#kein-internet-trotz-kabel) |
| WLAN, installiertes System | `nmcli device wifi list`, dann `nmcli device wifi connect 'WLAN_NAME' --ask` (oder Menü: `nmtui`) |
| WLAN, Live-USB-Stick | [WLAN mit iwctl](#wlan-mit-iwctl-live-usb-stick) |
| WLAN-Name enthält `!` (z.B. `FRITZ!Box 6670 JU`) | **einfache** Anführungszeichen, sonst `bash: event not found`; Schreibweise genau wie in der Liste |
| `iwctl device list` / `nmcli device` zeigt kein WLAN | Treiber fehlt → [Ältere MacBooks](#ältere-macbooks-broadcom-wlan) |

### WLAN mit iwctl (Live-USB-Stick)

`iwctl` ist auf dem Stick immer dabei, im installierten System nur mit Paket `iwd`.

```bash
rfkill unblock all
iwctl device list                         # Gerätename, meist wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect 'WLAN_NAME'   # fragt nach dem Passwort
```

Im installierten System nicht `iwd` und NetworkManager gleichzeitig laufen lassen.

### Ältere MacBooks (Broadcom-WLAN)

Z.B. MacBook Air 2014. Treiber `broadcom-wl` fehlt **auf dem Stick und im frischen System** →
WLAN geht erst mit Treiber. Bis dahin Internet per USB:

| Wenn | Dann |
|---|---|
| Android | Datenkabel, Einstellungen → Netzwerk & Internet → Hotspot & Tethering → *USB-Tethering* (Samsung: Verbindungen → Mobile Hotspot und Tethering). Teilt auch das WLAN des Handys. |
| iPhone | *Persönlicher Hotspot* an, „Vertrauen“ bestätigen (nutzt mobile Daten) |
| USB-LAN-Adapter | Kabel zum Router |
| Neuer Anschluss (`usb0`/`enp…` in `ip -br addr`) ohne IP | Tethering aus/an, Kabel neu stecken |

**Bei der Installation (`archinstall`):** Netzwerk *NetworkManager*, Zusätzliche Pakete `broadcom-wl`.

**Nachträglich**, erst Kernel prüfen:

```bash
uname -r     # endet auf -lts → linux-lts, sonst (z.B. 7.3.6-arch1-1) → linux
```

| Kernel | Installieren |
|---|---|
| `linux` | `sudo pacman -Syu broadcom-wl` |
| `linux-lts` | `sudo pacman -Syu broadcom-wl-dkms linux-lts-headers` |

```bash
sudo modprobe -r b43 bcma ssb 2>/dev/null; sudo modprobe wl
nmcli device wifi connect 'WLAN_NAME' --ask
```

| Wenn | Dann |
|---|---|
| `pacman -Syu` hat neuen Kernel installiert | neu starten statt `modprobe` |
| `modprobe: FATAL: Module wl not found` | Treiber für falschen Kernel gebaut. `sudo pacman -S linux-headers` (DKMS baut automatisch), `dkms status` muss `installed` für `uname -r` zeigen, dann `sudo modprobe wl`. Oder: `sudo pacman -R broadcom-wl-dkms && sudo pacman -S broadcom-wl`, neu starten. |
| WLAN verbunden | USB-Kabel kann ab |

**Stick mit Treiber (optional)**, auf einem Arch-Rechner bauen:

```bash
sudo pacman -S archiso
cp -r /usr/share/archiso/configs/releng ~/archlive
echo broadcom-wl >> ~/archlive/packages.x86_64
sudo mkarchiso -v -w /tmp/archiso-work -o ~/iso ~/archlive
```

ISO aus `~/iso/` auf den Stick. Dann geht `iwctl` schon dort; `broadcom-wl` trotzdem in `archinstall` mitinstallieren.

### Kein Internet trotz Kabel

Symptom: „Temporärer Fehler bei der Namensauflösung“. Ursache: kein DHCP-Dienst im installierten System.

```bash
ip -br addr            # LAN-Interface (z.B. enp3s0) mit 192.168.x.x?
ping -c 2 1.1.1.1      # reine IP erreichbar?
cat /etc/resolv.conf   # nameserver eingetragen?
```

| Wenn | Dann |
|---|---|
| keine IP-Adresse | Variante A **oder** B einrichten, nie beide |
| IP da, `1.1.1.1` erreichbar, kein DNS | A: NetworkManager neu starten; B: Symlink (letzte Zeile unten) setzen |

**A: NetworkManager** (empfohlen, auch WLAN):

```bash
sudo systemctl enable --now NetworkManager
```

`Unit NetworkManager.service not found` → vom Arch-Stick booten:

```bash
mount /dev/ROOT-PARTITION /mnt    # z.B. /dev/nvme0n1p2; btrfs zusätzlich: -o subvol=@
arch-chroot /mnt
pacman -S networkmanager
systemctl enable NetworkManager
exit
umount -R /mnt
reboot
```

**B: systemd-networkd** (vorinstalliert, nur LAN):

```bash
sudo tee /etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF
sudo systemctl enable --now systemd-networkd systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

Danach erneut `ping -c 3 archlinux.org`.

## 4. Git und Repo

```bash
sudo pacman -Syu --needed git
git clone https://github.com/grindgaming/dotfiles ~/dotfiles
```

## 5. Wiederherstellen

```bash
~/dotfiles/install.sh
```

Dauer 15–40 Min. (AUR-Pakete werden kompiliert). Keine pacman-/yay-Rückfragen; Schlüssel werden
zuerst aktualisiert, Paketkonflikte (z.B. `pulseaudio`/`pipewire-pulse`) zugunsten des Backups gelöst.

| Frage | Antwort |
|---|---|
| sudo-Passwort (einmal) | eigenes Passwort |
| NVIDIA deaktivieren? (nur NVIDIA + AMD-iGPU) | **j** = schläft dauerhaft, alles auf iGPU; **Enter** = wie Backup |
| Hardwarelast reduzieren? | **j** = Performance (kein Blur, keine Schatten, kein Live-Wallpaper-Autostart); **n** = Beauty; **Enter** = wie Backup |
| mainMod-Taste | **1** Alt, **2** Super, **Enter** = wie Backup |

Ohne Eingaben: `~/dotfiles/install.sh -y --mainmod alt` (oder `super`).
Am Ende Liste fehlgeschlagener Pakete; bei **„System wiederhergestellt! Bitte neu starten.“** → `reboot`.

## 6. Nach dem Neustart

SDDM → anmelden, **Hyprland** wählen.

| Wenn | Dann |
|---|---|
| Auflösung/Anordnung falsch | `nwg-displays` oder ML4W-Settings |
| `dotfiles backup` soll pushen | SSH-Key anlegen (Keys werden nicht gesichert, Klon nutzt HTTPS): |

```bash
ssh-keygen -t ed25519 -C "$USER@$(uname -n)" -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub        # bei https://github.com/settings/ssh/new eintragen
cd ~/dotfiles && git remote set-url origin git@github.com:grindgaming/dotfiles.git
ssh -T git@github.com            # einmal "yes"
```

## Falls etwas schiefgeht

| Wenn | Dann |
|---|---|
| AUR-Paket schlägt fehl | Skript macht weiter, Liste am Ende; `yay -S paketname` |
| Pakete „übersprungen“ | gibt es auf dieser Hardware nicht (z.B. `lib32-*` auf ARM), gewollt |
| „signature … is unknown trust“ / „ungültiges oder beschädigtes Paket“ | meist falsche Uhrzeit: `timedatectl` prüfen, `sudo pacman -Sy archlinux-keyring`, Skript neu starten |
| Skript bricht ab | `~/dotfiles/install.sh` erneut starten, Installiertes wird übersprungen |
| Ältere Nvidia (vor RTX 20xx/GTX 16xx) | `nvidia-open-dkms` passt nicht → Legacy-Treiber aus dem AUR |
| Dateien überschrieben | `$HOME`: `~/.dotfiles-backup/<datum>/`; `/etc`: Endung `.dotfiles-bak` |
| Keine Statusleiste/kein Dock | Quickshell nicht gestartet, meist fehlt `~/.mydotfiles` (Log von `ml4w-autostart`; Restore legt es seit 2026-11 selbst an). Sofort beheben: |

```bash
mkdir -p ~/.mydotfiles && hyprctl dispatch 'hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-autostart > ~/.mydotfiles/ml4w-autostart.log 2>&1")'
```
