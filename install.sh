#!/usr/bin/env bash

# ============================================================
#  install.sh — Richtet fokus ein
#  Einmalig ausführen mit: bash install.sh
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BOLD}  fokus — Installation${NC}"
echo ""

# Auf btrfs prüfen und Nutzer informieren
FS=$(df -T /etc/hosts 2>/dev/null | awk 'NR==2{print $2}')
if [[ "$FS" == "btrfs" ]]; then
    echo -e "  Dateisystem: ${CYAN}btrfs${NC} erkannt — Immutable-Modus via chmod"
else
    echo -e "  Dateisystem: ${CYAN}${FS}${NC} erkannt — Immutable-Modus via chattr"
fi

# chattr prüfen (nur relevant bei ext4)
if [[ "$FS" != "btrfs" ]] && ! command -v chattr &>/dev/null; then
    echo -e "  ${RED}Warnung:${NC} chattr nicht gefunden. Bitte e2fsprogs installieren:"
    echo -e "    Arch:   ${CYAN}sudo pacman -S e2fsprogs${NC}"
    echo -e "    Fedora: ${CYAN}sudo dnf install e2fsprogs${NC}"
    echo ""
fi

chmod +x "$SCRIPT_DIR/fokus.sh"
echo -e "  ${GREEN}✓${NC} fokus.sh als ausführbar markiert"

sudo cp "$SCRIPT_DIR/fokus.sh" /usr/local/bin/fokus
sudo chmod +x /usr/local/bin/fokus
echo -e "  ${GREEN}✓${NC} Skript nach /usr/local/bin/fokus kopiert"

if [[ ! -f /etc/hosts.backup ]]; then
    sudo cp /etc/hosts /etc/hosts.backup
    echo -e "  ${GREEN}✓${NC} Backup erstellt: /etc/hosts.backup"
else
    echo -e "  ${CYAN}·${NC} Backup existiert bereits (/etc/hosts.backup)"
fi

echo ""
echo -e "  ${GREEN}${BOLD}Installation abgeschlossen.${NC}"
echo ""
echo -e "  ${CYAN}sudo fokus start${NC}           Blocking aktivieren"
echo -e "  ${CYAN}sudo fokus stop${NC}            Blocking deaktivieren"
echo -e "  ${CYAN}sudo fokus lock <minuten>${NC}  stop für X Minuten sperren"
echo -e "  ${CYAN}fokus status${NC}               Status anzeigen"
echo ""
