# fokus

Website-Blocker auf Systemebene für Linux. Sperrt Domains über `/etc/hosts` und friert die Datei anschließend ein — unabhängig von Browser, VPN oder Browser-Extensions.

Kompatibel mit **ext4** und **btrfs**, getestet auf Arch-basierten Distributionen und Fedora.

## Voraussetzungen

- Linux mit bash
- `sudo`-Rechte
- `e2fsprogs` für `chattr` (nur bei ext4 — auf den meisten Systemen vorinstalliert)

## Installation

```bash
bash install.sh
```

Das Skript erkennt automatisch das Dateisystem, kopiert `fokus` nach `/usr/local/bin` und legt ein Backup der hosts-Datei unter `/etc/hosts.backup` an.

## Verwendung

```bash
sudo fokus start             # Blocking aktivieren
sudo fokus stop              # Blocking deaktivieren
sudo fokus lock <minuten>    # stop für X Minuten sperren
fokus status                 # Aktuellen Status anzeigen
```

### Beispiele

```bash
sudo fokus start         # Blocking an
sudo fokus lock 90       # stop für 90 Minuten deaktivieren
fokus status             # Zeit der Sperre anzeigen
sudo fokus stop          # schlägt fehl solange Sperre aktiv
sudo fokus lock 0        # Sperre sofort aufheben (Notfall)
sudo fokus stop          # jetzt möglich
```

## Domains konfigurieren

Die gesperrten Domains werden direkt in `fokus.sh` im `BLOCKED_SITES`-Array definiert:

```bash
BLOCKED_SITES=(
    "beispiel.com"
    "www.beispiel.com"
    "m.beispiel.com"
)
```

Es empfiehlt sich, immer alle Varianten einer Domain einzutragen — mit und ohne `www.`, sowie `m.` für mobile Subdomains. Nach einer Änderung muss das Skript neu installiert werden:

```bash
bash install.sh
```

## Wie es funktioniert

**Blocking:** Beim `start` werden alle Domains aus `BLOCKED_SITES` mit der Adresse `127.0.0.1` in `/etc/hosts` eingetragen. Das Betriebssystem liest diese Datei vor jeder DNS-Anfrage — die Domain wird ins Nichts umgeleitet, bevor irgendein Netzwerktraffic entsteht. Das Blocking greift auf Domain-Ebene: `beispiel.com`, `beispiel.com/seite` und alle weiteren Pfade sind gleichermaßen gesperrt.

**Immutable-Schutz:** Nach jeder Änderung wird die hosts-Datei eingefroren:
- **ext4:** via `chattr +i` — selbst root kann die Datei nicht bearbeiten
- **btrfs:** via `chmod 444` + root-Besitz — gleichwertiger Schutz

**Lock:** `fokus lock <minuten>` schreibt einen Unix-Timestamp in `/etc/fokus.lock` und friert diese Datei ebenfalls ein. Solange die Zeit nicht abgelaufen ist, verweigert `stop` die Ausführung. Mit `lock 0` kann die Sperre im Notfall jederzeit aufgehoben werden.

## Deinstallation

```bash
sudo fokus stop                      # Blocking deaktivieren (falls aktiv)
sudo rm /usr/local/bin/fokus         # Skript entfernen
sudo rm -f /etc/fokus.lock           # Lock-Datei entfernen (falls vorhanden)
```

## Hosts-Datei wiederherstellen

Falls etwas schiefläuft:

```bash
# ext4
sudo chattr -i /etc/hosts
sudo cp /etc/hosts.backup /etc/hosts

# btrfs
sudo chmod 644 /etc/hosts
sudo cp /etc/hosts.backup /etc/hosts
```
