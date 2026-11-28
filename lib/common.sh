# Gemeinsame Hilfsfunktionen für das dotfiles-Skript

msg()  { printf '\e[1;34m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\e[1;33m==> WARNUNG:\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m==> FEHLER:\e[0m %s\n' "$*" >&2; exit 1; }

# ask "Frage" [y|n] – Ja/Nein-Abfrage. Mit ASSUME_YES=1 oder ohne Terminal gilt der Default.
ask() {
    local question=$1 default=${2:-y} answer hint="[J/n]"
    [[ $default == n ]] && hint="[j/N]"
    if [[ ${ASSUME_YES:-0} == 1 || ! -t 0 ]]; then
        [[ $default == y ]]
        return
    fi
    read -rp "$question $hint " answer
    answer=${answer:-$default}
    [[ $answer =~ ^[YyJj] ]]
}

# read_list Datei – gibt die Einträge einer Liste ohne Kommentare und Leerzeilen aus
read_list() {
    [[ -f $1 ]] || return 0
    sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# filter_hw – entfernt hardware-spezifische Pakete (Muster aus config/hardware-packages.txt) aus stdin
filter_hw() {
    local patterns
    patterns=$(read_list "$REPO/config/hardware-packages.txt")
    if [[ -n $patterns ]]; then
        grep -Ev -f <(printf '%s\n' "$patterns") || true
    else
        cat
    fi
}

require_user() {
    [[ $EUID -ne 0 ]] || die "Bitte als normaler Benutzer ausführen (sudo wird bei Bedarf aufgerufen)."
}

hostname_short() { uname -n; }

# Rechnerspezifischer Teil des Repos (Hardware-Dateien, Paket- und Dienstlisten)
host_dir() { echo "$REPO/hosts/$(hostname_short)"; }

# apply_host_files backup_dir – Hardware-Dateien dieses Rechners nach $HOME.
# Neuer Rechner ohne hosts/<rechner>/: nur fehlende Dateien aus config/host-standard/
# (sonst fehlt z.B. monitors.lua und Hyprland startet im Emergency Mode).
apply_host_files() {
    local backup_dir=$1
    if [[ -d $(host_dir)/home ]]; then
        rsync -a --keep-dirlinks --backup --backup-dir="$backup_dir" "$(host_dir)/home/" "$HOME/"
    else
        rsync -a --keep-dirlinks --ignore-existing "$REPO/config/host-standard/home/" "$HOME/"
        info "Neuer Rechner: Standard-Hardwaredateien gesetzt (monitors.lua, hypridle.conf); mit \"dotfiles backup\" sichern."
    fi
}

# host_excludes – rsync-Ausschlussdatei mit den Pfaden aus config/host.txt (mit führendem "/")
host_excludes() {
    local f
    f=$(mktemp)
    read_list "$REPO/config/host.txt" | sed 's|^|/|' > "$f"
    echo "$f"
}

# union_lists ziel datei... – Vereinigung mehrerer Listen (für Neuinstallationen)
union_lists() {
    local target=$1; shift
    cat "$@" 2>/dev/null | sed '/^$/d' | sort -u > "$target"
}
