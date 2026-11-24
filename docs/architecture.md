# Architecture

## What is mirrored

**The archive (`/debian`) is complete.** It has every architecture Debian publishes, plus source, and every
suite the upstream carries: oldoldstable through sid, experimental, backports, proposed-updates. That is what
"all hardware Debian supports" means for a mirror, so `ARCH_INCLUDE` and `ARCH_EXCLUDE` stay empty.

On 2026-11-23 the archive was 2.19 TB in 1.7 million files (rsync's own total from the upstream). Debian's
[mirror size page](https://www.debian.org/mirror/size) gives a larger figure. The rsync total is what this
upstream actually sends.

**debian-cd (`/debian-cd`)** holds the images of the current release for every architecture: the installer
(netinst, DVD), the live images, and the jigdo files. It was 231 GB on 2026-11-23. Each point release replaces
the previous one.

**Debian ports (`debian-ports`, unofficial architectures such as loong64)** are not mirrored. It is another
archive, with its own upstream.

## Storage: LVM + XFS

- **Disk:** a dedicated virtual disk (6 TiB, thin-provisioned on the host) is the single physical volume of the
  volume group `vgdata`. One logical volume, `srv`, takes all of it.
- **Growing it:** enlarge the virtual disk, then `pvresize` and `lvextend -r`. XFS grows online. LVM makes this a
  two-command job with no downtime, and it also allows a second disk to be added to the VG.
- **Why XFS:**
  - A mirror is a few million files, most of them already compressed (`.deb`, `.xz`, `.iso`). They are written
    once and then read in parallel by many clients.
  - XFS handles large directories and parallel reads well, and allocates inodes dynamically (no inode count to
    size up front).
  - It is the usual choice for big Debian mirrors.
- **Why not btrfs with compression:**
  - The previous mirror used btrfs with `compress=zstd:15`. Level 15 is expensive on writes, and the data barely
    compresses, because packages and images are compressed already.
  - btrfs also adds copy-on-write fragmentation under rsync's constant rewrites.
  - None of btrfs' strengths (snapshots, checksummed RAID) is needed: the mirror can always be fetched again.
- **Mount options:** `noatime`, because every read would otherwise write metadata.
- **Free space:** discard is not enabled on the mount. A weekly `fstrim.timer` returns freed blocks to the host's
  thin pool; online discard slows XFS down.
- **On the virtual disk:** `discard=on`, so those trims reach the host, and `iothread=1`.

## Sync

- **The archive:**
  - It uses `ftpsync` (Debian package `ftpsync`), the tool Debian requires for mirrors. It syncs in two stages:
    the packages first, then the indices. Clients therefore never see an index that points at a missing file.
  - It runs from `ftpsync-cron.service` every 5 minutes after the previous run ended.
  - `ftpsync-cron` reads the upstream's trace over HTTP. It starts `ftpsync` only when the upstream serial
    changed, so a quiet upstream costs one HTTP request.
  - The previous mirror ran the same check from cron every 2 minutes.
- **Upstream:** `debian.c3sl.ufpr.br` (C3SL/UFPR, Curitiba), a push mirror that carries every architecture.
- **debian-cd:**
  - It uses `rsync`, with the options of the [Debian CD mirroring guide](https://www.debian.org/CD/mirroring/):
    hard links, `--delete-after`, `--delay-updates`. It runs twice a day.
  - The images change only at point releases, so more often would be wasted.
- **Process:**
  - Both run as the unprivileged user `mirror` (the old host ran them as root).
  - Their systemd units are sandboxed: read-only system, writes allowed only to the mirror tree, the logs and
    `/var/lib/mirror`.
  - They run at low CPU and IO priority, so serving clients comes first.

## Serving

- **HTTP (nginx):**
  - It runs with autoindex and caches open files.
  - It uses thread-pool IO (`aio threads`) for the large files.
  - Pool files get a 7-day `Expires` header and indices 5 minutes, which helps caching proxies.
- **Plain HTTP is not redirected to HTTPS:**
  - apt and the Debian installer verify everything against the archive's GPG signatures, so HTTP is safe.
  - A forced redirect breaks clients without CA certificates (an installer, a minimal container).
  - HTTPS is offered alongside it (Let's Encrypt, webroot challenge).
- **rsync (`rsyncd`):**
  - It uses the standard port 873, read only.
  - It hides rsync's temporary directories and ftpsync's lock files.
- **Never served:** hidden files and `Archive-Update-*` lock files.

## Host

- **Clock:** chrony uses the Blue3 NTP server first (`100.64.66.230`, `ntp.blue3.com.br`, `170.233.231.230`),
  with the Debian pool as a fallback.
- **Firewall (nftables):**
  - HTTP, HTTPS and rsync are open to everyone.
  - SSH and monitoring are allowed only from management sources. Those sources are kept in a file outside this
    public repository (`config/nftables/mgmt.nft.example` shows its shape).
- **Updates:** unattended security updates are on (`unattended-upgrades`).
- **Proxmox:** the QEMU guest agent is installed.
