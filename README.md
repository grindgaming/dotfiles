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
| Aktivierte Dienste, Gruppen, Login-Shell, Zeitzone, VS-Code-Erweiterungen | `state/` | – |

Hardware-spezifische Pakete (CPU-Microcode, Nvidia/AMD/Intel-Treiber, VM-Tools) werden **nicht**
gespeichert (`config/hardware-packages.txt`), sondern bei der Wiederherstellung neu erkannt.
Vor jedem Commit wird nach privaten Schlüsseln und Tokens gesucht. Bei einem Fund bricht das
Backup ab.

## Wiederherstellen auf einer frischen Arch-Installation

Schritt-für-Schritt-Anleitung mit allen Rückfragen und Fehlerbehebung: [WIEDERHERSTELLEN.md](WIEDERHERSTELLEN.md)

Voraussetzung: ein installiertes Arch (z.B. per `archinstall`) mit Benutzer, `sudo` und Internet.

```bash
sudo pacman -S --needed git
git clone https://github.com/grindgaming/dotfiles ~/dotfiles
~/dotfiles/install.sh                 # mit Rückfragen
~/dotfiles/install.sh --yes --mainmod super   # ohne Rückfragen
```

Ablauf:

1. `pacman.conf`: multilib (nur x86_64), Color, ParallelDownloads
2. Hardware erkennen (`dotfiles hardware` zeigt das Ergebnis vorab)
3. Offizielle Pakete installieren, dabei Pakete überspringen, die es auf der Architektur nicht
   gibt (z.B. `lib32-*` auf ARM)
4. `yay` installieren, dann die AUR-Pakete und Flatpaks
5. Configs nach `$HOME` kopieren. Überschriebene Dateien landen in `~/.dotfiles-backup/<datum>/`
6. Systemdateien nach `/etc` (Originale als `*.dotfiles-bak`), `locale-gen`, Zeitzone
7. ML4W-Dateien pro Rechner anlegen (`hypr/conf/monitor.lua`, `hypr/conf/environment.lua`)
8. mainMod-Taste wählen (Alt oder Super/Cmd)
9. Dienste aktivieren, Gruppen und Shell setzen, VS-Code-Erweiterungen installieren
10. `dotfiles` nach `~/.local/bin` verlinken

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
