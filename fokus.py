#!/usr/bin/env python3

# ============================================================
#  fokus — Website-Blocker auf Systemebene
# ============================================================

import os
import sys
import time
import shutil
import random
import string
import subprocess
from datetime import datetime
from pathlib import Path

# ---- Globale Pfade ----
HOSTS_FILE  = Path("/etc/hosts")
LOCK_FILE   = Path("/etc/fokus.lock")
CONF_FILE   = Path("/etc/fokus.conf")

MARKER_START = "# === FOKUS START ==="
MARKER_END   = "# === FOKUS ENDE ==="

# Fallback/Default Sites, falls keine Config existiert
DEFAULT_SITES =[
    "example.com"
]

KNOWN_BROWSERS =[
    "firefox", "chromium", "chromium-browser", "chrome",
    "google-chrome", "brave", "brave-browser", "opera",
    "vivaldi", "librewolf", "waterfox", "zen-browser"
]

# ---- ANSI-Farben ----
R  = "\033[0;31m"
G  = "\033[0;32m"
Y  = "\033[1;33m"
C  = "\033[0;36m"
B  = "\033[1m"
NC = "\033[0m"


# ============================================================
#  Hilfsfunktionen & Konfiguration
# ============================================================

def check_root() -> None:
    if os.geteuid() != 0:
        print(f"\n  {R}Fehler:{NC} Dieser Befehl benötigt Root-Rechte.")
        print(f"  Bitte setze ein {C}sudo{NC} vor den Befehl.\n")
        sys.exit(1)

def init_conf() -> None:
    """Erstellt die Config-Datei mit Standardwerten, falls sie nicht existiert."""
    if not CONF_FILE.exists():
        try:
            content = "# fokus Konfigurationsdatei\n# Trage hier pro Zeile eine Domain ein, die blockiert werden soll.\n\n"
            content += "\n".join(DEFAULT_SITES) + "\n"
            CONF_FILE.write_text(content)
        except OSError:
            pass

def get_blocked_sites() -> list[str]:
    """Liest die zu blockierenden Seiten aus /etc/fokus.conf."""
    init_conf()
    sites =[]
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                sites.append(line)
    return sites if sites else DEFAULT_SITES

def is_active() -> bool:
    try:
        return MARKER_START in HOSTS_FILE.read_text()
    except OSError:
        return False

def freeze(path: Path) -> None:
    """Schützt die Datei vor Veränderungen (chattr +i)."""
    result = subprocess.run(["chattr", "+i", str(path)], capture_output=True)
    if result.returncode != 0:
        os.chown(path, 0, 0)
        os.chmod(path, 0o444)

def unfreeze(path: Path) -> None:
    """Hebt den Schutz der Datei auf."""
    subprocess.run(["chattr", "-i", str(path)], capture_output=True)
    try:
        os.chmod(path, 0o644)
    except OSError:
        pass

def flush_dns() -> None:
    """Leert die DNS Caches des Systems."""
    if shutil.which("systemctl"):
        result = subprocess.run(["systemctl", "is-active", "systemd-resolved"],
            capture_output=True, text=True
        )
        if result.stdout.strip() == "active":
            subprocess.run(["resolvectl", "flush-caches"], capture_output=True)

    if shutil.which("nscd"):
        subprocess.run(["nscd", "-i", "hosts"], capture_output=True)

def hint_browsers() -> None:
    """Sucht laufende Browser und gibt einen simplen Hinweis aus."""
    found = []
    for browser in KNOWN_BROWSERS:
        if subprocess.run(["pgrep", "-x", browser], capture_output=True).returncode == 0:
            found.append(browser)

    if found:
        print(f"  {Y}Hinweis:{NC} Laufende Browser erkannt ({C}{', '.join(found)}{NC}).")
        print(f"  Bitte starte deinen Browser kurz neu, damit die Sperre greift.\n")
    else:
        print(f"  Bitte starte deinen Browser kurz neu, damit die Sperre greift.\n")
        


# ============================================================
#  Lock-Logik
# ============================================================

def lock_remaining() -> int:
    if not LOCK_FILE.exists():
        return 0
    try:
        until = int(LOCK_FILE.read_text().strip())
        remaining = until - int(time.time())
        return max(0, remaining)
    except (ValueError, OSError):
        return 0

def is_locked() -> bool:
    return lock_remaining() > 0

def format_remaining(secs: int) -> str:
    h, remainder = divmod(secs, 3600)
    m, s = divmod(remainder, 60)
    if h > 0: return f"{h}h {m:02d}m {s:02d}s"
    elif m > 0: return f"{m}m {s:02d}s"
    return f"{s}s"


# ============================================================
#  Befehle
# ============================================================

def cmd_start() -> None:
    if is_active():
        print(f"\n  {Y}Fokus ist bereits aktiv.{NC}")
        cmd_status()
        sys.exit(0)

    sites = get_blocked_sites()
    if not sites:
        print(f"\n  {R}Fehler:{NC} Keine Domains in {CONF_FILE} konfiguriert.\n")
        sys.exit(1)

    unfreeze(HOSTS_FILE)

    now_str = datetime.now().strftime("%d.%m.%Y %H:%M")
    block_lines =["", MARKER_START, f"# Aktiviert: {now_str}"]

    for site in sites:
        block_lines.append(f"127.0.0.1   {site}")
        block_lines.append(f"::1         {site}")

    block_lines.extend([MARKER_END, ""])

    with HOSTS_FILE.open("a") as f:
        f.write("\n".join(block_lines))

    freeze(HOSTS_FILE)
    flush_dns()

    print(f"\n  {G}{B}Fokus aktiviert.{NC}")
    print(f"  {G}{datetime.now().strftime('%H:%M Uhr')}{NC} — Gesperrte Domains (siehe {CONF_FILE}):\n")
    for site in sites:
        if not site.startswith(("www.", "m.")):
            print(f"  {C}·{NC} {site}")
    print(f"\n  Deaktivieren:  {C}stop{NC}")
    print(f"  Sperren:       {C}lock <minuten>{NC}\n")

    hint_browsers()

def cmd_stop() -> None:
    if not is_active():
        print(f"\n  {Y}Fokus ist nicht aktiv.{NC}\n")
        sys.exit(0)

    if is_locked():
        remaining = lock_remaining()
        print(f"\n  {R}{B}Stoppen nicht möglich.{NC}")
        print(f"  Sperre aktiv — noch {format_remaining(remaining)}.")
        print(f"\n  {C}lock 0{NC}?\n")
        sys.exit(1)

    unfreeze(HOSTS_FILE)

    content = HOSTS_FILE.read_text()
    lines = content.splitlines()

    filtered =[]
    inside = False
    for line in lines:
        if line.strip() == MARKER_START: inside = True; continue
        if line.strip() == MARKER_END: inside = False; continue
        if not inside: filtered.append(line)

    while filtered and filtered[-1].strip() == "":
        filtered.pop()

    HOSTS_FILE.write_text("\n".join(filtered) + "\n")

    freeze(HOSTS_FILE)
    flush_dns()

    print(f"\n  {R}{B}Fokus deaktiviert.{NC}")
    print(f"  {R}{datetime.now().strftime('%H:%M Uhr')}{NC} — Alle Domains wieder erreichbar.\n")

def cmd_lock(minutes_arg: str | None) -> None:
    if minutes_arg is None or not minutes_arg.isdigit():
        print(f"\n  {R}Fehler:{NC} Bitte Anzahl Minuten angeben.")
        print(f"  Beispiel: {C}lock 90{NC}\n")
        sys.exit(1)

    minutes = int(minutes_arg)

    if minutes == 0:
        if not LOCK_FILE.exists():
            print(f"\n  {Y}Es ist aktuell keine Sperre aktiv.{NC}\n")
            return

        print(f"\n  {R}{B}WARNUNG:{NC} Du bist dabei, deine Fokus-Sperre vorzeitig abzubrechen.")
        print(f"  Atme tief durch. Willst du wirklich schon aufhören?\n")
        time.sleep(3)

        challenge = ''.join(random.choices(string.ascii_uppercase + string.digits, k=12))
        print(f"  Um abzubrechen, tippe folgenden Code exakt ab: {Y}{challenge}{NC}")

        try:
            answer = input(f"  > ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n\n  {G}Abgebrochen. Bleib fokussiert!{NC}\n")
            return

        if answer != challenge:
            print(f"\n  {R}Falscher Code.{NC} Sperre bleibt aktiv.\n")
            return

        unfreeze(LOCK_FILE)
        LOCK_FILE.unlink()
        print(f"\n  {Y}Sperre aufgehoben.{NC}")
        print(f"  {C}stop{NC} ist wieder verfügbar.\n")
        return

    until = int(time.time()) + minutes * 60
    until_str = datetime.fromtimestamp(until).strftime("%H:%M Uhr")

    if LOCK_FILE.exists():
        unfreeze(LOCK_FILE)
    LOCK_FILE.write_text(str(until))
    freeze(LOCK_FILE)

    print(f"\n  {G}{B}Sperre aktiv.{NC}")
    print(f"  {G}stop{NC} ist gesperrt bis {C}{until_str}{NC} ({minutes} Minuten).")
    print(f"\n  Notfall-Aufhebung: {C}lock 0{NC}\n")

def cmd_status() -> None:
    print()
    sites = get_blocked_sites()

    if is_active():
        start_time = ""
        for line in HOSTS_FILE.read_text().splitlines():
            if line.startswith("# Aktiviert:"):
                start_time = line.replace("# Aktiviert: ", "").strip()

        print(f"  Status:    {G}{B}AKTIV{NC}")
        print(f"  Seit:      {C}{start_time}{NC}")

        if is_locked():
            print(f"  Sperre:    {R}stop gesperrt — noch {format_remaining(lock_remaining())}{NC}")
        else:
            print(f"  Sperre:    {Y}keine{NC}")

        print(f"\n  Gesperrte Domains ({CONF_FILE}):")
        for site in sites:
            if not site.startswith(("www.", "m.")):
                print(f"    {C}·{NC} {site}")
    else:
        print(f"  Status:    {Y}INAKTIV{NC}")
        print(f"  Alle Domains aus {CONF_FILE} sind erreichbar.")
    print()

def print_help() -> None:
    print(f"""
  {B}fokus{NC} — Website-Blocker

  {C}start{NC}           Blocking aktivieren
  {C}stop{NC}            Blocking deaktivieren
  {C}lock <minuten>{NC}  stop für X Minuten sperren
  {C}status{NC}          Status anzeigen

  {Y}Konfiguration:{NC} Bearbeite die Datei {B}/etc/fokus.conf{NC}
""")

def main() -> None:
    args = sys.argv[1:]
    cmd  = args[0] if args else ""

    if cmd == "start": check_root(); cmd_start()
    elif cmd == "stop": check_root(); cmd_stop()
    elif cmd == "lock": check_root(); cmd_lock(args[1] if len(args) > 1 else None)
    elif cmd == "status": cmd_status()
    elif cmd == "help": print_help()
    else: print_help()

if __name__ == "__main__":
    main()
