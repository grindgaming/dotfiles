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
Unterwegs kommen diese Fragen:

| Frage | Antwort |
|---|---|
| sudo-Passwort | eigenes Passwort |
| pacman: „Installation fortsetzen?“ | **Enter** |
| Konflikt `pulseaudio` / `pipewire-pulse` | **j** (wie auf dem bisherigen System) |
| Auswahl bei mehreren Anbietern (z.B. Schriftarten) | **Enter** (Standard) |
| „Diese Dateien nach /etc übernehmen?“ | **Enter** (ja) |
| mainMod-Taste | **1** Alt, **2** Super, **Enter** = wie im Backup |

Ohne Rückfragen: `~/dotfiles/install.sh --yes --mainmod alt`. Bei Konflikten ist die Variante mit
Rückfragen aber übersichtlicher.

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
- **Skript bricht ab:** Einfach erneut `~/dotfiles/install.sh` starten. Bereits Installiertes wird übersprungen.
- **Ältere Nvidia-Karte** (vor RTX 20xx/GTX 16xx): Der automatisch gewählte Treiber `nvidia-open-dkms`
  passt nicht, hier wird ein Legacy-Treiber aus dem AUR benötigt.
- **Überschriebene Dateien:** Was beim Wiederherstellen in `$HOME` ersetzt wurde, liegt in
  `~/.dotfiles-backup/<datum>/`. Ersetzte Dateien in `/etc` haben die Endung `.dotfiles-bak`.
