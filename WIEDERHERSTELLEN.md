# Wiederherstellen auf einer frischen Arch-Installation

Voraussetzung: Arch ist installiert (z.B. mit `archinstall`), der Rechner ist neu gestartet
und der USB-Stick entfernt. Das Repo ist öffentlich, der Klon funktioniert also ohne GitHub-Login.

## 1. Als normaler Benutzer anmelden

Auf der Konsole mit dem **normalen Benutzer** anmelden, nicht als `root`. Das Skript verweigert sonst den Start.

Falls bei der Installation **kein** Benutzer angelegt wurde, als `root` anmelden und ausführen:

```bash
useradd -m -G wheel BENUTZERNAME
passwd BENUTZERNAME
EDITOR=nano visudo     # Zeile "# %wheel ALL=(ALL:ALL) ALL" auskommentieren (# entfernen), speichern
exit
```

Danach als dieser Benutzer anmelden.

## 2. Deutsche Tastatur für die Konsole

```bash
sudo loadkeys de
```

Nicht nötig, wenn in `archinstall` schon `de` gewählt wurde.

## 3. Internet prüfen

```bash
ping -c 3 archlinux.org
```

- **LAN-Kabel:** klappt meist sofort.
- **WLAN** (bei Installation mit NetworkManager):

  ```bash
  nmcli device wifi list
  nmcli device wifi connect "DEIN_WLAN_NAME" --ask
  ```

  Bequemer mit Menü: `nmtui`.

### WLAN mit `iwctl` (Live-ISO, z.B. vor `archinstall`)

Am einfachsten, wenn kein Kabel da ist. `iwctl` gehört zu `iwd` und ist auf dem Arch-USB-Stick
immer dabei; auf dem installierten System nur, wenn `iwd` mitinstalliert wurde.

```bash
rfkill unblock all                 # falls WLAN gesperrt ist
iwctl device list                  # Name des WLAN-Geräts, meist wlan0
iwctl station wlan0 scan
iwctl station wlan0 get-networks   # verfügbare WLANs
iwctl station wlan0 connect "DEIN_WLAN_NAME"   # fragt nach dem Passwort
ping -c 3 archlinux.org
```

Interaktiv geht es auch: `iwctl` starten, dieselben Befehle ohne `iwctl` davor, `exit` zum Beenden.

- **`device list` ist leer:** Es fehlt der WLAN-Treiber, siehe nächster Abschnitt.
- Auf dem installierten System nicht `iwd` und NetworkManager gleichzeitig laufen lassen;
  dort WLAN wie oben mit `nmcli`/`nmtui` einrichten.

### Ältere MacBooks (z.B. MacBook Air 2014): WLAN geht erst mit Treiber

Diese MacBooks haben einen Broadcom-WLAN-Chip. Der nötige Treiber `broadcom-wl` ist **weder auf
dem Arch-USB-Stick noch im frisch installierten System**. Das WLAN funktioniert also zunächst
**auf keinen Fall**, man braucht für Installation und Treiber eine Netzwerkverbindung über USB:

- **USB-Tethering vom Handy:** Handy per Datenkabel anschließen, dann Android: Einstellungen →
  Netzwerk & Internet → Hotspot & Tethering → *USB-Tethering* (Samsung: Verbindungen → Mobile
  Hotspot und Tethering); iPhone: *Persönlicher Hotspot* an, „Vertrauen“ bestätigen.
  Android teilt dabei auch sein WLAN, ohne Datenvolumen.
- **oder USB-LAN-Adapter** mit Kabel zum Router.

Das Handy bzw. der Router vergibt die IP-Adresse, der USB-Stick und NetworkManager übernehmen sie
automatisch. Prüfen mit `ip -br addr` (neuer Anschluss `usb0`/`enp…` mit Adresse) und
`ping -c 3 archlinux.org`.

**Bei der Installation:** In `archinstall` als Netzwerk *NetworkManager* wählen und unter
*Zusätzliche Pakete* `broadcom-wl` eintragen (bei `linux-lts` stattdessen `broadcom-wl-dkms`
und `linux-lts-headers`). Dann geht WLAN nach dem Neustart direkt.

**Treiber nachträglich installieren** (installiertes System, Internet per USB):

```bash
sudo pacman -Syu broadcom-wl            # bei linux-lts: broadcom-wl-dkms linux-lts-headers
sudo modprobe -r b43 bcma ssb 2>/dev/null; sudo modprobe wl   # oder einfach neu starten
nmcli device wifi connect "DEIN_WLAN_NAME" --ask
```

Wenn `pacman -Syu` einen neuen Kernel installiert hat, lädt `wl` erst nach einem Neustart.
Danach kann das USB-Kabel ab.

**USB-Stick mit Treiber (optional):** Mit `archiso` lässt sich eine eigene Arch-ISO bauen, die
`broadcom-wl` enthält (auf einem laufenden Arch-Rechner):

```bash
sudo pacman -S archiso
cp -r /usr/share/archiso/configs/releng ~/archlive
echo broadcom-wl >> ~/archlive/packages.x86_64
sudo mkarchiso -v -w /tmp/archiso-work -o ~/iso ~/archlive
```

Die fertige ISO aus `~/iso/` wie gewohnt auf den Stick schreiben. Dann geht `iwctl` schon auf dem
Stick; `broadcom-wl` muss trotzdem in `archinstall` mitinstalliert werden.

### Kein Internet trotz Kabel („Temporärer Fehler bei der Namensauflösung“)

Dann läuft kein Dienst, der per DHCP eine IP-Adresse holt und den DNS-Server einträgt.
Die Live-ISO erledigt das automatisch, das installierte System nicht. Zuerst prüfen:

```bash
ip -br addr            # hat das LAN-Interface (z.B. enp3s0) eine 192.168.x.x-Adresse?
ping -c 2 1.1.1.1      # klappt der Ping auf eine reine IP-Adresse?
cat /etc/resolv.conf   # steht dort ein nameserver?
```

- **Keine IP-Adresse:** Es fehlt ein Netzwerkdienst. Eine der beiden Varianten unten einrichten.
- **IP vorhanden und `1.1.1.1` erreichbar, aber kein DNS:** `/etc/resolv.conf` ist leer oder
  zeigt ins Leere. Bei Variante B den Symlink setzen; bei Variante A NetworkManager neu starten.

Nur **eine** Variante verwenden, nie beide gleichzeitig.

#### Variante A: NetworkManager (empfohlen, kann auch WLAN)

```bash
sudo systemctl enable --now NetworkManager
```

Falls NetworkManager nicht installiert ist (`Unit NetworkManager.service not found`), lässt er sich
ohne Internet nicht nachinstallieren. Dann vom Arch-USB-Stick booten und dort installieren:

```bash
mount /dev/ROOT-PARTITION /mnt    # z.B. /dev/nvme0n1p2; bei btrfs zusätzlich: -o subvol=@
arch-chroot /mnt
pacman -S networkmanager
systemctl enable NetworkManager
exit
umount -R /mnt
reboot
```

#### Variante B: systemd-networkd (schon vorinstalliert, nur LAN)

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

Danach erneut `ping -c 3 archlinux.org` ausführen.

## 4. Git installieren und Repo klonen

```bash
sudo pacman -Syu --needed git
git clone https://github.com/grindgaming/dotfiles ~/dotfiles
```

## 5. Wiederherstellung starten

```bash
~/dotfiles/install.sh
```

Das dauert je nach Internet und Rechner etwa **15–40 Minuten**, weil AUR-Pakete kompiliert werden.
Das Skript läuft ohne pacman-/yay-Rückfragen durch: Signaturschlüssel werden zuerst aktualisiert,
Paketkonflikte (z.B. `pulseaudio` / `pipewire-pulse`) automatisch zugunsten des Backups gelöst.
Es gibt nur diese Eingaben:

| Frage | Antwort |
|---|---|
| sudo-Passwort (einmal am Anfang) | eigenes Passwort |
| NVIDIA-Karte deaktivieren? (nur bei NVIDIA + AMD-iGPU) | **j** = schläft dauerhaft, alles auf der iGPU; **Enter** = wie im Backup |
| Hardwarelast reduzieren? | **j** = Performance (kein Blur, keine Schatten, kein Live-Wallpaper-Autostart), **n** = Beauty; **Enter** = wie im Backup |
| mainMod-Taste | **1** Alt, **2** Super, **Enter** = wie im Backup |

Komplett ohne Eingaben (alles wie im Backup): `~/dotfiles/install.sh -y --mainmod alt` (oder `super`).
Pakete, die sich nicht installieren ließen, stehen am Ende in einer Zusammenfassung.

Wenn am Ende **„System wiederhergestellt! Bitte neu starten.“** erscheint:

```bash
reboot
```

## 6. Nach dem Neustart

Es erscheint der **SDDM-Anmeldebildschirm**: anmelden und **Hyprland** wählen.

- **Monitor einstellen**, falls Auflösung oder Anordnung nicht stimmen: `nwg-displays` oder die ML4W-Settings.
- **Backups pushen:** Der Klon nutzt HTTPS, und SSH-Keys werden bewusst nicht gesichert.
  Einen neuen Key für diesen Rechner anlegen:

  ```bash
  ssh-keygen -t ed25519 -C "$USER@$(uname -n)" -N "" -f ~/.ssh/id_ed25519
  cat ~/.ssh/id_ed25519.pub        # bei https://github.com/settings/ssh/new eintragen
  cd ~/dotfiles && git remote set-url origin git@github.com:grindgaming/dotfiles.git
  ssh -T git@github.com            # Test; einmal "yes" eingeben
  ```

  Danach funktioniert `dotfiles backup`.

## Falls etwas schiefgeht

- **AUR-Paket schlägt fehl:** Das Skript macht weiter und listet die fehlgeschlagenen Pakete am Ende auf.
  Nachinstallieren mit `yay -S paketname`.
- **Pakete werden „übersprungen“:** Diese gibt es auf dieser Hardware nicht (z.B. `lib32-*` auf ARM). Gewollt.
- **„signature … is unknown trust“ / „ungültiges oder beschädigtes Paket“:** Das Skript aktualisiert
  den Schlüsselbund automatisch. Tritt der Fehler trotzdem auf, stimmt meist die Uhrzeit nicht:
  `timedatectl` prüfen, dann `sudo pacman -Sy archlinux-keyring` und das Skript erneut starten.
- **Skript bricht ab:** Einfach erneut `~/dotfiles/install.sh` starten. Bereits Installiertes wird übersprungen.
- **Ältere Nvidia-Karte** (vor RTX 20xx/GTX 16xx): Der automatisch gewählte Treiber `nvidia-open-dkms`
  passt nicht, hier wird ein Legacy-Treiber aus dem AUR benötigt.
- **Überschriebene Dateien:** Was beim Wiederherstellen in `$HOME` ersetzt wurde, liegt in
  `~/.dotfiles-backup/<datum>/`. Ersetzte Dateien in `/etc` haben die Endung `.dotfiles-bak`.
- **Keine Statusleiste oben (auch kein Dock):** Quickshell wurde nicht gestartet. Meist fehlt
  `~/.mydotfiles`, wohin `hypr/conf/autostart.lua` das Log von `ml4w-autostart` schreibt (legt das
  Restore seit 2026-11 selbst an). Sofort beheben ohne Neuanmeldung:
  `mkdir -p ~/.mydotfiles && hyprctl dispatch 'hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-autostart > ~/.mydotfiles/ml4w-autostart.log 2>&1")'`
