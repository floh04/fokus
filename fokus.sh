#!/usr/bin/env bash

# ============================================================
#  fokus — Website-Blocker auf Systemebene
#  Kompatibel mit ext4 und btrfs, getestet auf Arch & Fedora
#
#  Verwendung:
#    sudo fokus start           Blocking aktivieren
#    sudo fokus stop            Blocking deaktivieren
#    sudo fokus lock <minuten>  stop für X Minuten sperren
#    fokus status               Aktuellen Status anzeigen
#
#  Websites konfigurieren: BLOCKED_SITES-Array weiter unten
# ============================================================

HOSTS_FILE="/etc/hosts"
LOCK_FILE="/etc/fokus.lock"
MARKER_START="# === FOKUS START ==="
MARKER_END="# === FOKUS ENDE ==="

# ---- Hier eigene Domains eintragen ----
BLOCKED_SITES=(
    "youtube.com"
    "www.youtube.com"
    "m.youtube.com"
    "youtu.be"
    "instagram.com"
    "www.instagram.com"
    "chess.com"
    "www.chess.com"
    "lichess.org"
    "www.lichess.org"
)
# ---------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
#  Hilfsfunktionen
# ============================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Fehler:${NC} Dieser Befehl benötigt sudo."
        echo -e "  ${CYAN}sudo fokus $1${NC}"
        exit 1
    fi
}

is_active() {
    grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null
}

# Erkennt das Dateisystem von /etc und gibt "ext4" oder "btrfs" (oder anderes) zurück
get_filesystem() {
    df -T "$HOSTS_FILE" 2>/dev/null | awk 'NR==2{print $2}'
}

# Macht eine Datei immutable — je nach Dateisystem unterschiedlich
freeze() {
    local file="$1"
    local fs
    fs=$(get_filesystem)

    if [[ "$fs" == "btrfs" ]]; then
        # btrfs: Datei auf root-Besitz setzen und nur lesbar machen
        chown root:root "$file"
        chmod 444 "$file"
    else
        # ext4 und andere: chattr
        chattr +i "$file" 2>/dev/null || {
            # Fallback falls chattr nicht verfügbar
            chown root:root "$file"
            chmod 444 "$file"
        }
    fi
}

# Macht eine Datei wieder beschreibbar
unfreeze() {
    local file="$1"
    # chattr -i immer zuerst versuchen — funktioniert auf ext4, schadet auf btrfs nicht
    chattr -i "$file" 2>/dev/null || true
    chmod 644 "$file" 2>/dev/null || true
}

flush_dns() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        resolvectl flush-caches 2>/dev/null || true
    fi
    if command -v nscd &>/dev/null; then
        nscd -i hosts 2>/dev/null || true
    fi
}

# ============================================================
#  Lock-Logik
# ============================================================

# Gibt verbleibende Sekunden der Sperre zurück (0 = keine Sperre)
lock_remaining() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        echo 0
        return
    fi
    local until
    until=$(cat "$LOCK_FILE" 2>/dev/null)
    local now
    now=$(date +%s)
    if [[ -z "$until" || "$now" -ge "$until" ]]; then
        echo 0
    else
        echo $(( until - now ))
    fi
}

is_locked() {
    [[ $(lock_remaining) -gt 0 ]]
}

format_remaining() {
    local secs=$1
    local h=$(( secs / 3600 ))
    local m=$(( (secs % 3600) / 60 ))
    local s=$(( secs % 60 ))
    if [[ $h -gt 0 ]]; then
        printf "%dh %02dm %02ds" $h $m $s
    elif [[ $m -gt 0 ]]; then
        printf "%dm %02ds" $m $s
    else
        printf "%ds" $s
    fi
}

# ============================================================
#  Befehle
# ============================================================

cmd_start() {
    if is_active; then
        echo -e "${YELLOW}Fokus ist bereits aktiv.${NC}"
        cmd_status
        exit 0
    fi

    unfreeze "$HOSTS_FILE"

    {
        echo ""
        echo "$MARKER_START"
        echo "# Aktiviert: $(date '+%d.%m.%Y %H:%M')"
        for site in "${BLOCKED_SITES[@]}"; do
            echo "127.0.0.1   $site"
        done
        echo "$MARKER_END"
    } >> "$HOSTS_FILE"

    freeze "$HOSTS_FILE"
    flush_dns

    echo -e ""
    echo -e "${GREEN}${BOLD}  Fokus aktiviert.${NC}"
    echo -e "${GREEN}  $(date '+%H:%M Uhr')${NC} — Gesperrte Domains:"
    echo ""
    for site in "${BLOCKED_SITES[@]}"; do
        [[ "$site" != www.* && "$site" != m.* ]] && echo -e "  ${CYAN}·${NC} $site"
    done
    echo ""
    echo -e "  Deaktivieren:  ${CYAN}sudo fokus stop${NC}"
    echo -e "  Sperren:       ${CYAN}sudo fokus lock <minuten>${NC}"
    echo ""
}

cmd_stop() {
    if ! is_active; then
        echo -e "${YELLOW}Fokus ist nicht aktiv.${NC}"
        exit 0
    fi

    if is_locked; then
        local remaining
        remaining=$(lock_remaining)
        echo -e ""
        echo -e "${RED}${BOLD}  Gestoppt werden nicht möglich.${NC}"
        echo -e "  Sperre aktiv — noch $(format_remaining $remaining)."
        echo -e ""
        echo -e "  Notfall-Aufhebung: ${CYAN}sudo fokus lock 0${NC}"
        echo ""
        exit 1
    fi

    unfreeze "$HOSTS_FILE"
    sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    while [[ $(tail -c1 "$HOSTS_FILE" | wc -c) -eq 1 ]] && [[ $(tail -1 "$HOSTS_FILE") == "" ]]; do
        sed -i '$ d' "$HOSTS_FILE"
    done

    freeze "$HOSTS_FILE"
    flush_dns

    echo -e ""
    echo -e "${RED}${BOLD}  Fokus deaktiviert.${NC}"
    echo -e "  ${RED}$(date '+%H:%M Uhr')${NC} — Alle Domains wieder erreichbar."
    echo ""
}

cmd_lock() {
    local minutes="$1"

    if [[ -z "$minutes" || ! "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Fehler:${NC} Bitte Anzahl Minuten angeben."
        echo -e "  ${CYAN}sudo fokus lock 90${NC}"
        exit 1
    fi

    # Notfall: lock 0 hebt die Sperre sofort auf
    if [[ "$minutes" -eq 0 ]]; then
        if [[ -f "$LOCK_FILE" ]]; then
            unfreeze "$LOCK_FILE"
            rm -f "$LOCK_FILE"
        fi
        echo -e ""
        echo -e "${YELLOW}  Sperre aufgehoben.${NC}"
        echo -e "  ${CYAN}sudo fokus stop${NC} ist wieder verfügbar."
        echo ""
        return
    fi

    local until
    until=$(( $(date +%s) + minutes * 60 ))
    local until_human
    until_human=$(date -d "@$until" '+%H:%M Uhr' 2>/dev/null || date -r "$until" '+%H:%M Uhr' 2>/dev/null)

    # Lock-Datei schreiben und einfrieren
    if [[ -f "$LOCK_FILE" ]]; then
        unfreeze "$LOCK_FILE"
    fi
    echo "$until" > "$LOCK_FILE"
    freeze "$LOCK_FILE"

    echo -e ""
    echo -e "${GREEN}${BOLD}  Sperre aktiv.${NC}"
    echo -e "  ${GREEN}stop${NC} ist gesperrt bis ${CYAN}${until_human}${NC} (${minutes} Minuten)."
    echo ""
    echo -e "  Notfall-Aufhebung: ${CYAN}sudo fokus lock 0${NC}"
    echo ""
}

cmd_status() {
    echo ""
    if is_active; then
        START_TIME=$(grep "# Aktiviert:" "$HOSTS_FILE" | tail -1 | sed 's/# Aktiviert: //')
        echo -e "  Status:    ${GREEN}${BOLD}AKTIV${NC}"
        echo -e "  Seit:      ${CYAN}$START_TIME${NC}"

        if is_locked; then
            local remaining
            remaining=$(lock_remaining)
            echo -e "  Sperre:    ${RED}stop gesperrt — noch $(format_remaining $remaining)${NC}"
        else
            echo -e "  Sperre:    ${YELLOW}keine${NC}"
        fi

        echo ""
        echo -e "  Gesperrte Domains:"
        for site in "${BLOCKED_SITES[@]}"; do
            [[ "$site" != www.* && "$site" != m.* ]] && echo -e "    ${CYAN}·${NC} $site"
        done
    else
        echo -e "  Status:    ${YELLOW}INAKTIV${NC}"
        echo -e "  Alle Domains sind erreichbar."
    fi
    echo ""
}

# ============================================================
#  Hauptlogik
# ============================================================

case "$1" in
    start)   check_root "start"; cmd_start ;;
    stop)    check_root "stop";  cmd_stop ;;
    lock)    check_root "lock";  cmd_lock "$2" ;;
    status)  cmd_status ;;
    *)
        echo -e ""
        echo -e "  ${BOLD}fokus${NC} — Website-Blocker auf Systemebene"
        echo -e ""
        echo -e "  ${CYAN}sudo fokus start${NC}           Blocking aktivieren"
        echo -e "  ${CYAN}sudo fokus stop${NC}            Blocking deaktivieren"
        echo -e "  ${CYAN}sudo fokus lock <minuten>${NC}  stop für X Minuten sperren"
        echo -e "  ${CYAN}fokus status${NC}               Status anzeigen"
        echo -e ""
        ;;
esac
