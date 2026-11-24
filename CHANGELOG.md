# Changelog

## 1.0.0 - 2026-11-24

- **New mirror host replaces the previous one:**
  - Debian 13.
  - LVM + XFS on a dedicated 6 TiB disk, instead of btrfs with zstd level 15.
  - ftpsync run by an unprivileged user from sandboxed systemd units.
  - nginx without a forced HTTPS redirect.
  - rsyncd on the standard port.
  - nftables.
  - chrony on the Blue3 NTP server.
  - Unattended security updates.
- **Mirrored:**
  - The full archive: every architecture and source.
  - debian-cd: the current release, every architecture.
- **Repository:**
  - `scripts/deploy.sh` installs every file under `config/`.
  - `docs/` holds the design, the install steps and the operations runbook.
