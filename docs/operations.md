# Operations

## Is it fresh?

```bash
mirror-status            # last archive sync (from the trace), last debian-cd sync, disk; exit code 0/1/2
systemctl list-timers ftpsync-cron.timer debian-cd-sync.timer
```

- **The archive is fresh when its trace is under 12 hours old.**
  - The upstream publishes about four times a day.
  - Our trace is `/srv/mirror/debian/project/trace/mirror.blue3.com.br`.
  - From outside: `curl http://mirror.blue3.com.br/debian/project/trace/mirror.blue3.com.br`.
- **For Zabbix:**
  - `UserParameter=mirror.status,/usr/local/bin/mirror-status --quiet; echo $?`
  - Alert on a value other than 0.

## Logs

| What | Where |
|---|---|
| Archive sync | `/var/log/ftpsync/ftpsync.log` (summary), `rsync-ftpsync.log` (files), `rsync-ftpsync.error` |
| Archive sync runs | `journalctl -u ftpsync-cron` |
| debian-cd sync | `journalctl -u debian-cd-sync` |
| HTTP | `/var/log/nginx/mirror-access.log`, `mirror-error.log` |
| rsync daemon | `/var/log/rsyncd.log` |

## Sync by hand

```bash
systemctl start ftpsync-cron.service      # only syncs when the upstream changed
sudo -u mirror -H ftpsync                 # forces a full archive sync
systemctl start debian-cd-sync.service
```

Never run a second `ftpsync` while one runs. Its lock is `/srv/mirror/debian/Archive-Update-in-Progress-mirror.blue3.com.br`.

## Adding space

```bash
# 1. grow the VM's data disk on the hypervisor (Proxmox: Hardware > Hard Disk > Disk Action > Resize)
# 2. on the mirror:
echo 1 > /sys/class/block/sdb/device/rescan
pvresize /dev/sdb
lvextend -r -l +100%FREE vgdata/srv       # -r grows XFS online
```

A second disk works as well: `pvcreate /dev/sdc`, `vgextend vgdata /dev/sdc`, then the same `lvextend`.

## TLS certificate

The HTTP-01 challenge is answered from `/var/www/letsencrypt`, outside the mirror tree:

```bash
certbot certonly --webroot -w /var/www/letsencrypt -d mirror.blue3.com.br -d mirrors.blue3.com.br
# uncomment the 443 server in /etc/nginx/sites-available/mirror (config/nginx/mirror.conf), then
nginx -t && systemctl reload nginx
```

`certbot.timer` renews the certificate. Add a deploy hook to reload nginx:
`echo -e '#!/bin/sh\nsystemctl reload nginx' > /etc/letsencrypt/renewal-hooks/deploy/nginx && chmod +x $_`.

The challenge only works once the public name points at this host (see Cutover).

## Cutover from the previous mirror

1. Let the new host sync on its own for a day. `mirror-status` must say fresh.
2. Compare it with the old host: the serial in both traces is the same, and `apt update` from a client using
   `http://<new address>/debian` works.
3. Point the public name at the new host. That is the NAT rule of the public address, or the DNS record of
   `mirror.blue3.com.br` and `mirrors.blue3.com.br`.
4. Issue the certificate ("TLS certificate"), enable HTTPS.
5. **rsync clients:**
   - The old host listened on port 2873 and the new one on the standard 873.
   - Its modules pointed at paths that no longer existed, so no client depended on it.
6. Stop the syncs on the old host (cron), keep it off for a week, then retire it.

## Troubleshooting

- **Writes hang, the guest log shows `task rsync blocked for more than 120 seconds` in XFS:**
  - Look at `/sys/block/sdb/inflight`.
  - A non-zero count that never drops points below the guest.
  - On Proxmox, check that the disk has no `mbps_wr`/`iops_wr` limit (see install.md, step 1).
- **`ftpsync-cron` fails with a curl error:**
  - The upstream's trace is unreachable over HTTP. Nothing syncs until it is back.
  - Check `curl -I http://debian.c3sl.ufpr.br/debian/project/trace/debian.c3sl.ufpr.br`.
- **Changing upstream:**
  - Set `RSYNC_HOST` (and `RSYNC_PATH`) in `config/ftpsync/ftpsync.conf`, then deploy.
  - Pick a push mirror that carries every architecture.
  - Debian's list: https://www.debian.org/mirror/list-full.
