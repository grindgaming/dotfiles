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
