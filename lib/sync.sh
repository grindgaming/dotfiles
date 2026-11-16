# dotfiles sync – alle Arch-Rechner auf einem gemeinsamen Stand halten (Zweig main)
#
# Ablauf: eigene Änderungen sichern (Commit) → Änderungen der anderen Rechner holen
# (git pull --rebase) → in $HOME anwenden (inkl. Löschungen) → Oberfläche neu laden → pushen.
# Hardware-Dateien (config/host.txt) bleiben je Rechner unter hosts/<rechner>/.
# Pakete werden nie automatisch installiert (sudo), fehlende nur gemeldet.

sync_notify() {
    # $1 = low|normal|critical, $2 = Titel, $3 = Text
    command -v notify-send >/dev/null || return 0
    notify-send -a dotfiles -u "$1" "$2" "$3" 2>/dev/null || true
}

# Hyprland-Instanz finden, auch wenn sync vom systemd-Timer gestartet wird
sync_hypr_env() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && return 0
    local d
    d=$(ls -td "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/ 2>/dev/null | head -n1)
    [[ -n $d ]] || return 1
    export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$d")
}

# Gemeinsame Configs + Hardware-Dateien dieses Rechners nach $HOME
sync_apply_home() {
    local path backup_dir hostex
    backup_dir="$HOME/.dotfiles-backup/sync-$(date +%Y%m%d-%H%M%S)"
    hostex=$(host_excludes)
    while IFS= read -r path; do
        [[ -e $REPO/home/$path ]] || continue
        if [[ -d $REPO/home/$path ]]; then
            mkdir -p "$HOME/$path"
            # --delete: auf dem anderen Rechner gelöschte Dateien verschwinden auch hier.
            # Ausgeschlossenes (exclude.txt, host.txt) wird nie gelöscht.
            rsync -a --keep-dirlinks --delete --backup --backup-dir="$backup_dir/$path" \
                --exclude-from="$REPO/config/exclude.txt" --exclude-from="$hostex" \
                "$REPO/home/$path/" "$HOME/$path/"
        else
            mkdir -p "$(dirname "$HOME/$path")"
            rsync -a --backup --backup-dir="$backup_dir/$(dirname "$path")" \
                "$REPO/home/$path" "$HOME/$path"
        fi
    done < <(read_list "$REPO/config/home.txt")
    rm -f "$hostex"
    if [[ -d $(host_dir)/home ]]; then
        rsync -a --keep-dirlinks --backup --backup-dir="$backup_dir" "$(host_dir)/home/" "$HOME/"
    fi
    [[ -d $backup_dir ]] && info "Ersetzte/gelöschte Dateien gesichert in $backup_dir"
    return 0
}

# Neu laden, was sich geändert hat ($1 = Liste geänderter Repo-Pfade)
sync_reload() {
    local changed=$1
    if grep -q '\.config/systemd/user/' <<<"$changed"; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    if sync_hypr_env && command -v hyprctl >/dev/null; then
        if grep -q '\.config/hypr/' <<<"$changed"; then
            hyprctl reload >/dev/null 2>&1 && info "Hyprland neu geladen."
        fi
        if grep -qE '\.config/(quickshell|ml4w-statusbar)/' <<<"$changed" \
            && [[ -x $HOME/.config/ml4w/scripts/ml4w-reload-statusbar ]]; then
            "$HOME/.config/ml4w/scripts/ml4w-reload-statusbar" >/dev/null 2>&1 &
            info "Statusleiste neu geladen."
        fi
    fi
}

# Pakete aus der gemeinsamen Liste, die hier fehlen, nur melden
sync_missing_packages() {
    local missing
    missing=$(comm -13 <(pacman -Qq | sort -u) \
        <(cat "$REPO/packages/pacman.txt" "$REPO/packages/aur.txt" 2>/dev/null | filter_hw | sort -u))
    [[ -n $missing ]] || return 0
    warn "Auf diesem Rechner fehlen Pakete der anderen Rechner:"
    sed 's/^/    /' <<<"$missing"
    info "Installieren: yay -S --needed $(tr '\n' ' ' <<<"$missing")"
    sync_notify normal "dotfiles: Pakete fehlen" "$(wc -l <<<"$missing") Pakete, siehe: dotfiles status"
}

cmd_sync() {
    local take=0 before after changed
    while (( $# )); do
        case $1 in
            --uebernehmen) take=1 ;;
            *) die "Unbekannte Option für sync: $1" ;;
        esac
        shift
    done
    require_user

    # Nie zwei Läufe gleichzeitig (Timer + Hand)
    exec 9>"$REPO/.git/dotfiles-sync.lock"
    flock -n 9 || die "Es läuft bereits ein dotfiles sync."

    [[ -z $(git -C "$REPO" ls-files -u) ]] || die "Repo hat ungelöste Konflikte – bitte erst beheben."
    git -C "$REPO" rev-parse --abbrev-ref HEAD | grep -qx main \
        || die "Repo ist nicht auf Zweig main."

    if (( take )); then
        # Erstes Einrichten: Stand vom Repo übernehmen, ohne vorher die eigene Abweichung zu sichern
        msg "Gemeinsamen Stand übernehmen"
        git -C "$REPO" pull -q --rebase origin main || die "git pull fehlgeschlagen."
        sync_apply_home
        sync_reload ".config/hypr/ .config/quickshell/ .config/systemd/user/"
    else
        cmd_backup --no-push -m "Sync: $(date '+%Y-%m-%d %H:%M') ($(hostname_short))"

        msg "Änderungen der anderen Rechner holen"
        before=$(git -C "$REPO" rev-parse HEAD)
        if ! git -C "$REPO" pull -q --rebase origin main; then
            git -C "$REPO" rebase --abort 2>/dev/null || true
            sync_notify critical "dotfiles sync: Konflikt" \
                "Beide Rechner haben dieselbe Datei geändert. Nichts angewendet, bitte von Hand lösen."
            die "Konflikt mit Änderungen eines anderen Rechners. Nichts angewendet.
Lösen: cd ~/dotfiles && git pull --rebase origin main"
        fi
        after=$(git -C "$REPO" rev-parse HEAD)
        # Nur die Commits der anderen Rechner zählen (eigener Commit liegt obendrauf)
        changed=$(git -C "$REPO" diff --name-only "$before" "$after" -- home "hosts/$(hostname_short)" 2>/dev/null || true)
        if [[ -n $changed ]]; then
            msg "Änderungen anwenden"
            sed 's/^/    /' <<<"$changed"
            sync_apply_home
            sync_reload "$changed"
            sync_notify low "dotfiles sync" "$(wc -l <<<"$changed") Dateien von anderem Rechner übernommen"
        else
            info "Keine neuen Änderungen von anderen Rechnern."
        fi
    fi

    sync_missing_packages

    msg "Nach GitHub pushen"
    git -C "$REPO" push -q origin HEAD:main || die "Push fehlgeschlagen."
    info "Fertig."
}
