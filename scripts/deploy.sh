#!/bin/bash
# Installs or updates the mirror on a Debian 13 host from this repository. Idempotent: run it again after any change.
#   scripts/deploy.sh <user@host> [--no-sync] [--no-firewall]
# The user needs passwordless sudo. /srv must already be mounted (docs/install.md, "Storage").
#   --no-sync      install everything but leave the two sync timers disabled (while /srv is being seeded)
#   --no-firewall  skip nftables (no config/nftables/mgmt.nft yet)
set -euo pipefail
HOST=${1:?usage: deploy.sh user@host [--no-sync] [--no-firewall]}; shift
SYNC=1; FW=1
for a in "$@"; do case $a in --no-sync) SYNC=0 ;; --no-firewall) FW=0 ;; *) echo "unknown option $a"; exit 2 ;; esac; done
cd "$(dirname "$0")/.."
SSH=(ssh -a -o BatchMode=yes "$HOST")
STAGE=/tmp/debian-mirror-deploy.$$

"${SSH[@]}" "mountpoint -q /srv" || { echo "/srv is not mounted on $HOST"; exit 1; }
if [ $FW = 1 ] && [ ! -s config/nftables/mgmt.nft ]; then
    echo "config/nftables/mgmt.nft is missing (copy mgmt.nft.example, list the management sources) or use --no-firewall"; exit 1
fi
tar -cf - config scripts | "${SSH[@]}" "mkdir -p $STAGE && tar -xf - -C $STAGE"

"${SSH[@]}" "sudo bash -s -- $STAGE $SYNC $FW" <<'EOF'
set -euo pipefail
S=$1 SYNC=$2 FW=$3
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get -qq update
apt-get -qq -y install ftpsync rsync nginx chrony nftables unattended-upgrades apt-listchanges \
    certbot curl xfsprogs qemu-guest-agent >/dev/null

# the sync user; its home is outside the served tree (ftpsync keeps state under ~)
getent passwd mirror >/dev/null || adduser --system --group --home /var/lib/mirror --shell /usr/sbin/nologin mirror >/dev/null
usermod -d /var/lib/mirror mirror
install -d -o mirror -g mirror -m 0755 /var/lib/mirror /var/lib/mirror/lock /srv/mirror \
    /srv/mirror/debian /srv/mirror/debian-cd /srv/mirror/blue3-inventory
install -d -o mirror -g mirror -m 0750 /var/log/ftpsync
install -d -m 0755 /var/www/letsencrypt

install -d -m 0755 /etc/ftpsync
install -m 0644 $S/config/ftpsync/ftpsync.conf /etc/ftpsync/ftpsync.conf
install -m 0755 $S/scripts/debian-cd-sync /usr/local/sbin/debian-cd-sync
install -m 0755 $S/scripts/mirror-status /usr/local/bin/mirror-status
install -m 0644 $S/config/systemd/*.service $S/config/systemd/*.timer /etc/systemd/system/
install -m 0644 $S/config/chrony/blue3.sources /etc/chrony/sources.d/blue3.sources
install -m 0644 $S/config/apt/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
install -m 0644 $S/config/rsyncd/rsyncd.conf /etc/rsyncd.conf
install -m 0644 $S/config/nginx/mirror.conf /etc/nginx/sites-available/mirror
install -m 0644 $S/config/nginx/mirror-locations.conf /etc/nginx/snippets/mirror-locations.conf
install -m 0644 $S/config/nginx/mirror-tuning.conf /etc/nginx/conf.d/mirror-tuning.conf
ln -sfn /etc/nginx/sites-available/mirror /etc/nginx/sites-enabled/mirror
rm -f /etc/nginx/sites-enabled/default

systemctl daemon-reload
chronyc reload sources >/dev/null
nginx -t -q && systemctl reload-or-restart nginx
systemctl enable -q --now rsync nginx chrony qemu-guest-agent 2>/dev/null || systemctl enable -q --now rsync nginx chrony
systemctl restart rsync
if [ "$SYNC" = 1 ]; then
    systemctl enable -q --now ftpsync-cron.timer debian-cd-sync.timer
else
    echo "sync timers left disabled (--no-sync)"
fi

if [ "$FW" = 1 ]; then
    install -d -m 0755 /etc/nftables.d
    install -m 0640 $S/config/nftables/mgmt.nft /etc/nftables.d/mgmt.nft
    install -m 0755 $S/config/nftables/nftables.conf /etc/nftables.conf
    nft -c -f /etc/nftables.conf
    # safety net: the ruleset is flushed again in 3 minutes unless the caller confirms it can still log in
    systemd-run -q --unit=nft-rollback --on-active=180 /usr/sbin/nft flush ruleset
    nft -f /etc/nftables.conf
    echo "firewall loaded; rollback armed for 3 minutes"
fi
rm -rf "$S"
EOF

if [ $FW = 1 ]; then
    # a fresh connection proves SSH still passes the new ruleset
    if ssh -a -o BatchMode=yes -o ConnectTimeout=15 "$HOST" "sudo systemctl stop nft-rollback.timer && sudo systemctl enable -q nftables"; then
        echo "firewall confirmed and enabled at boot"
    else
        echo "could not log in again: the rollback flushes the ruleset within 3 minutes"; exit 1
    fi
fi
"${SSH[@]}" "/usr/local/bin/mirror-status || true"
