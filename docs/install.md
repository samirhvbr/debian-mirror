# Building a mirror host from scratch

The steps that built mirror.blue3.com.br in November 2026. Each one is safe to repeat.

## 1. The VM

- **System:** Debian 13, 8 vCPU, 32 GiB RAM, a 60 GiB system disk, and a user with passwordless sudo.
- **Data disk:** add a second disk, 6 TiB, `discard=on`, `iothread=1`, on bulk storage.
- **Do not set a bandwidth or IOPS limit on that disk while the VM writes to it.**
  - On 2026-11-23, `mbps_wr`/`iops_wr` added to the running VM left 24 writes stuck inside QEMU's throttle filter.
  - The guest's XFS then blocked for 21 hours.
  - Removing the limit released them at once.
  - To slow the initial copy down, use rsync's `--bwlimit` inside the guest instead.

## 2. Storage

```bash
blkid /dev/sdb                       # must print nothing: the disk is empty
pvcreate /dev/sdb
vgcreate vgdata /dev/sdb
lvcreate -n srv -l 100%FREE vgdata
mkfs.xfs -K -L srv /dev/vgdata/srv   # -K: the thin disk is fresh, no need to discard 6 TiB
echo "UUID=$(blkid -s UUID -o value /dev/vgdata/srv) /srv xfs defaults,noatime 0 2" >> /etc/fstab
mount /srv
systemctl enable --now fstrim.timer
```

The whole disk is the physical volume (no partition table), so growing is `pvresize` with no partition to edit.

## 3. Everything else

From a workstation with this repository:

```bash
cp config/nftables/mgmt.nft.example config/nftables/mgmt.nft   # then list the real management sources
scripts/deploy.sh admin@host --no-sync
```

- **What it does:**
  - installs the packages;
  - creates the user `mirror` (home `/var/lib/mirror`) and the tree `/srv/mirror/{debian,debian-cd}`;
  - installs every file under `config/`;
  - enables nginx, rsyncd and chrony.
- **The firewall:**
  - It is loaded with a 3-minute automatic rollback.
  - The rollback is cancelled only after a fresh SSH login succeeds.
  - Only then is the firewall enabled at boot.
- **`--no-sync`:** leaves the two sync timers off.

## 4. The first copy

- **From the internet:** the first `ftpsync` run fetches about 2.2 TB from the upstream, and debian-cd 231 GB.
- **What we did instead:** seeded `/srv/mirror` from the previous mirror over the LAN. Then `ftpsync` only
  transfers what changed since.

```bash
# on the new host, as root, from the old one (read access is enough there)
rsync -rlptH --chown=mirror:mirror --exclude='*-Update-in-Progress-*' \
      old-host:/srv/mirror/debian/ /srv/mirror/debian/
rsync -rlptH --chown=mirror:mirror old-host:/srv/mirror/debian-cd/ /srv/mirror/debian-cd/
```

The copy keeps the old host's trace file. `ftpsync-cron` sees a serial different from the upstream's and runs a
full sync, which removes whatever is stale.

## 5. Start syncing

```bash
scripts/deploy.sh admin@host            # without --no-sync: enables ftpsync-cron.timer and debian-cd-sync.timer
ssh admin@host 'sudo systemctl start ftpsync-cron.service debian-cd-sync.service; mirror-status'
```

## 6. TLS and the public name

See [operations.md](operations.md): "TLS certificate" and "Cutover".
