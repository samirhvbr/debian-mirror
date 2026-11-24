# debian-mirror

Build and operation of **mirror.blue3.com.br**, the Debian mirror of [Blue3 Internet](https://blue3.com.br)
in Porto Alegre, Brazil. It serves:

| Path | Content | Upstream | Refresh |
|---|---|---|---|
| `/debian` | The full Debian archive: every architecture, plus source, every suite | `debian.c3sl.ufpr.br::debian` | `ftpsync`, when the upstream trace changes (checked every 5 min) |
| `/debian-cd` | Installation and live images of the current release, every architecture | `ftp.br.debian.org::debian-cd` | `rsync`, twice a day |
| `/blue3-inventory` | Blue3's own small apt repository | local | by hand |

Over HTTP, HTTPS and rsync (`rsync://mirror.blue3.com.br/debian`, `/debian-cd`).

## Layout

- **Host:** Debian 13 VM (8 vCPU, 32 GiB) on the Blue3 Proxmox cluster. The system disk is 60 GiB. The data
  disk is a separate 6 TiB virtual disk.
- **Storage:** LVM (`vgdata/srv`) with XFS on `/srv`, mounted `noatime`, with a weekly `fstrim`. It grows
  online. See [docs/architecture.md](docs/architecture.md) for why it is XFS and not btrfs with compression.
- **Sizes measured on 2026-11-23:**
  - archive: 2.19 TB in 1.7 M files;
  - debian-cd: 231 GB.
- **Sync user:** `mirror`, unprivileged, with its home in `/var/lib/mirror`. Systemd units run the syncs, and
  they are sandboxed (`ProtectSystem=strict`).
- **Clock:** chrony, using the Blue3 NTP server first.

## Repository

| Path | What |
|---|---|
| [config/](config/) | Every file installed on the host: ftpsync, systemd units, nginx, rsyncd, chrony, nftables, apt |
| [scripts/deploy.sh](scripts/deploy.sh) | Installs or updates the host from this repository (idempotent) |
| [scripts/debian-cd-sync](scripts/debian-cd-sync) | The debian-cd sync |
| [scripts/mirror-status](scripts/mirror-status) | Freshness check; its exit code works for monitoring |
| [docs/architecture.md](docs/architecture.md) | Design and the reasons behind it |
| [docs/install.md](docs/install.md) | Building a host from scratch |
| [docs/operations.md](docs/operations.md) | Daily operation, growth, TLS, cutover, troubleshooting |

## Quick checks

```bash
mirror-status                                   # last archive and debian-cd sync, disk
systemctl list-timers ftpsync-cron.timer debian-cd-sync.timer
journalctl -u ftpsync-cron -n 50                # the last ftpsync run
tail /var/log/ftpsync/ftpsync.log
```
