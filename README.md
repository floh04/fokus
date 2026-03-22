# fokus

A system-level website blocker for Linux. Blocks domains via `/etc/hosts` and freezes the file afterwards — independent of browser, VPN, or browser extensions.

Compatible with **ext4** and **btrfs**, tested on Arch-based distributions.

## Requirements

- Linux with bash
- `sudo` privileges
- `e2fsprogs` for `chattr` (ext4 only — pre-installed on most systems)

## Installation

```bash
bash install.sh
```

The script automatically detects the filesystem, copies `fokus` to `/usr/local/bin`, and creates a backup of your hosts file at `/etc/hosts.backup`.

## Usage

```bash
sudo fokus start            # Enable blocking
sudo fokus stop             # Disable blocking
sudo fokus lock <minutes>   # Prevent stop for X minutes
fokus status                # Show current status
```

### Examples

```bash
sudo fokus start        # Enable blocking
sudo fokus lock 90      # Disable stop for 90 minutes
fokus status            # Show remaining lock time
sudo fokus stop         # Fails while lock is active
sudo fokus lock 0       # Remove lock immediately (emergency)
sudo fokus stop         # Now works
```

## Configuring domains

Blocked domains are defined directly in `fokus.sh` in the `BLOCKED_SITES` array:

```bash
BLOCKED_SITES=(
    "example.com"
    "www.example.com"
    "m.example.com"
)
```

It is recommended to always add all variants of a domain — with and without `www.`, as well as `m.` for mobile subdomains. After any change, reinstall the script:

```bash
bash install.sh
```

## How it works

**Blocking:** On `start`, all domains from `BLOCKED_SITES` are added to `/etc/hosts` pointing to `127.0.0.1` (your local machine). The OS reads this file before any DNS lookup — the domain is redirected to nowhere before any network traffic is sent. Blocking works at the domain level: `example.com`, `example.com/page`, and all other paths are blocked equally.

**Immutable protection:** After every change, the hosts file is frozen:
- **ext4:** via `chattr +i` — even root cannot edit the file
- **btrfs:** via `chmod 444` + root ownership — equivalent protection

**Lock:** `fokus lock <minutes>` writes a Unix timestamp to `/etc/fokus.lock` and freezes that file as well. As long as the time has not elapsed, `stop` will refuse to execute. Use `lock 0` to remove the lock immediately in an emergency.

## Uninstallation

```bash
sudo fokus stop                      # Disable blocking (if active)
sudo rm /usr/local/bin/fokus         # Remove script
sudo rm -f /etc/fokus.lock           # Remove lock file (if present)
```

## Restoring the hosts file

If something goes wrong:

```bash
# ext4
sudo chattr -i /etc/hosts
sudo cp /etc/hosts.backup /etc/hosts

# btrfs
sudo chmod 644 /etc/hosts
sudo cp /etc/hosts.backup /etc/hosts
```
