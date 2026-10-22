# dotfiles backup – aktuellen Systemzustand ins Repo schreiben, committen und pushen

backup_packages() {
    msg "Paketlisten"
    pacman -Qqen | filter_hw | sort -u > "$REPO/packages/pacman.txt"
    pacman -Qqem | grep -v -- '-debug$' | filter_hw | sort -u > "$REPO/packages/aur.txt"
    info "$(wc -l < "$REPO/packages/pacman.txt") offizielle, $(wc -l < "$REPO/packages/aur.txt") AUR-Pakete"

    if command -v flatpak >/dev/null; then
        flatpak list --app --columns=application 2>/dev/null | sort -u > "$REPO/packages/flatpak.txt"
        info "$(wc -l < "$REPO/packages/flatpak.txt") Flatpaks"
    fi
}

backup_home() {
    msg "Konfigurationen aus \$HOME"
    local path missing=()
    mkdir -p "$REPO/home"
    while IFS= read -r path; do
        if [[ -e $HOME/$path ]]; then
            # --relative behält den Pfad bei, --delete hält das Repo synchron
            rsync -a --relative --delete --delete-excluded \
                --exclude-from="$REPO/config/exclude.txt" \
                "$HOME/./$path" "$REPO/home/"
        else
            missing+=("$path")
        fi
    done < <(read_list "$REPO/config/home.txt")
    (( ${#missing[@]} == 0 )) || info "Nicht vorhanden (übersprungen): ${missing[*]}"
}

backup_etc() {
    msg "Systemdateien aus /etc"
    local path
    mkdir -p "$REPO/system"
    while IFS= read -r path; do
        path=${path#/}
        [[ -e /$path ]] || continue
        rsync -rlpt --relative --delete "/./$path" "$REPO/system/" 2>/dev/null \
            || warn "Konnte /$path nicht lesen"
    done < <(read_list "$REPO/config/etc.txt")
}

backup_state() {
    msg "Dienste, Gruppen, Shell, Zeitzone"
    systemctl list-unit-files --state=enabled --type=service,socket,timer --no-legend 2>/dev/null \
        | awk '{print $1}' | sort -u > "$REPO/state/services-system.txt"
    systemctl --user list-unit-files --state=enabled --type=service,socket,timer --no-legend 2>/dev/null \
        | awk '{print $1}' | sort -u > "$REPO/state/services-user.txt" || true
    id -nG | tr ' ' '\n' | grep -vx "$(id -gn)" | sort -u > "$REPO/state/groups.txt"
    getent passwd "$USER" | cut -d: -f7 > "$REPO/state/shell.txt"
    readlink /etc/localtime | sed 's|.*/zoneinfo/||' > "$REPO/state/timezone.txt"
    if command -v code >/dev/null; then
        code --list-extensions 2>/dev/null | sort -u > "$REPO/state/vscode-extensions.txt" || true
    fi
}

# Bricht ab, wenn offensichtliche Geheimnisse im Commit landen würden
check_secrets() {
    local hits
    hits=$(git -C "$REPO" grep --cached -lE \
        -e 'BEGIN [A-Z ]*PRIVATE KEY' \
        -e 'ghp_[A-Za-z0-9]{36}' -e 'github_pat_[A-Za-z0-9_]{20,}' \
        -e 'sk-ant-[A-Za-z0-9_-]{20,}' -e 'sk-[A-Za-z0-9]{40,}' \
        -e 'AKIA[0-9A-Z]{16}' -e 'xox[abp]-[A-Za-z0-9-]{10,}' \
        -- . ':!lib/backup.sh' || true)
    if [[ -n $hits ]]; then
        git -C "$REPO" reset -q
        die "Mögliche Geheimnisse gefunden, Backup abgebrochen:
$hits
Datei in config/exclude.txt eintragen oder bereinigen und erneut versuchen."
    fi
}

cmd_backup() {
    local push=1 message=""
    while (( $# )); do
        case $1 in
            --no-push) push=0 ;;
            -m|--message) message=$2; shift ;;
            *) die "Unbekannte Option für backup: $1" ;;
        esac
        shift
    done
    require_user

    backup_packages
    backup_home
    backup_etc
    backup_state

    msg "Git"
    git -C "$REPO" add -A
    check_secrets
    if git -C "$REPO" diff --cached --quiet; then
        info "Keine Änderungen seit dem letzten Backup."
    else
        git -C "$REPO" diff --cached --stat | tail -n 1
        git -C "$REPO" commit -q -m "${message:-Auto-Backup: $(date '+%Y-%m-%d %H:%M') ($(hostname_short))}"
        info "Commit erstellt."
    fi
    if (( push )); then
        git -C "$REPO" push -q -u origin HEAD && info "Nach GitHub gepusht."
    fi
}
