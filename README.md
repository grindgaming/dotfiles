# dotfiles

Mein Arch-Linux-Setup (ML4W, Hyprland, Kitty, Rofi, Waybar), per Befehl nach GitHub gesichert
und auf beliebiger Hardware wiederherstellbar.

## Sichern

```bash
dotfiles backup            # sichern, committen, pushen
dotfiles backup --no-push  # nur lokal committen
dotfiles status            # was hat sich seit dem letzten Backup geändert?
dotfiles autobackup on     # täglich automatisch sichern (systemd-User-Timer)
```

Gesichert werden:

| Was | Wo im Repo | Konfiguriert in |
|---|---|---|
| Explizit installierte Pakete (offiziell, AUR, Flatpak) | `packages/` | – |
| Configs aus `$HOME` (hypr, ml4w, waybar, rofi, kitty, …) | `home/` | `config/home.txt` |
| Ausgewählte Systemdateien (Locale, Tastatur, SDDM, zram) | `system/etc/` | `config/etc.txt` |
| Aktivierte Dienste, Gruppen, Login-Shell, Zeitzone, VS-Code-Erweiterungen, aktives Wallpaper | `state/` | – |

Hardware-spezifische Pakete (CPU-Microcode, Nvidia/AMD/Intel-Treiber, VM-Tools) werden **nicht**
gespeichert (`config/hardware-packages.txt`), sondern bei der Wiederherstellung neu erkannt.
Vor jedem Commit wird nach privaten Schlüsseln und Tokens gesucht. Bei einem Fund bricht das
Backup ab.

## Wiederherstellen auf einer frischen Arch-Installation

Schritt-für-Schritt-Anleitung mit allen Rückfragen und Fehlerbehebung: [WIEDERHERSTELLEN.md](WIEDERHERSTELLEN.md)

Voraussetzung: ein installiertes Arch (z.B. per `archinstall`) mit Benutzer, `sudo` und Internet.

```bash
sudo pacman -Syu --needed git
git clone https://github.com/grindgaming/dotfiles ~/dotfiles
~/dotfiles/install.sh                     # fragt nach NVIDIA, Modus und mainMod-Taste
~/dotfiles/install.sh -y --mainmod super  # ganz ohne Eingaben (Werte aus dem Backup)
```

Ablauf:

1. Uhrzeit (NTP) und Signaturschlüssel aktualisieren, `pacman.conf`: multilib (nur x86_64), Color, ParallelDownloads
2. Hardware erkennen (`dotfiles hardware` zeigt das Ergebnis vorab)
3. Offizielle Pakete installieren, dabei Pakete überspringen, die es auf der Architektur nicht
   gibt (z.B. `lib32-*` auf ARM)
4. `yay` installieren, dann die AUR-Pakete und Flatpaks
5. Configs nach `$HOME` kopieren. Überschriebene Dateien landen in `~/.dotfiles-backup/<datum>/`
6. Nur bei erkannter NVIDIA-Karte (mit AMD-iGPU): fragen, ob sie deaktiviert werden soll.
   Dann schläft sie dauerhaft, alles läuft auf der iGPU, Programme gezielt mit `nvidia-run` auf der dGPU
7. Fragen, ob die Hardwarelast reduziert werden soll (**Performance**-Modus: kein Blur, keine Schatten,
   kein Live-Wallpaper-Autostart). Sonst **Beauty**-Modus mit den Einstellungen aus dem Backup
8. Systemdateien nach `/etc` (Originale als `*.dotfiles-bak`), `locale-gen`, Zeitzone.
   Die NVIDIA-Stromspar-Dateien nur, wenn die Karte deaktiviert wurde
9. ML4W-Dateien pro Rechner anlegen (`hypr/conf/monitor.lua`, `hypr/conf/environment.lua`)
10. mainMod-Taste wählen (Alt oder Super/Cmd)
11. Dienste aktivieren, Gruppen und Shell setzen, VS-Code-Erweiterungen installieren
12. `dotfiles` nach `~/.local/bin` verlinken

Die Antworten landen als Schalter in `~/.config/ml4w/settings/` (`nvidia-dgpu`, `hardware-mode`,
`live-wallpaper-autostart`) und werden mitgesichert. Bei der nächsten Wiederherstellung sind sie die Vorgabe.

Danach neu starten.

## Bewusst nicht enthalten

- `/etc/fstab`, Hostname, Bootloader, `mkinitcpio.conf`: hängen an Festplatte bzw. Hardware
- WLAN-Passwörter, SSH- und GPG-Schlüssel: Geheimnisse gehören nicht in Git
- Browser-Profile und große Daten
- Ältere Nvidia-Karten (vor RTX 20xx/GTX 16xx) brauchen statt `nvidia-open-dkms` einen
  Legacy-Treiber aus dem AUR

## Anpassen

- Weitere Ordner sichern: Pfad in `config/home.txt` eintragen
- Datei ausschließen: Muster in `config/exclude.txt`
- Weitere Systemdatei: Pfad in `config/etc.txt` (nur hardware-unabhängige Dateien!)
