#!/bin/bash
set -euo pipefail
umask 077

for variable in DB_HOST DB_NAME DB_USER; do
	[[ -n "${!variable:-}" ]] || { echo "Missing ${variable}."; exit 1; }
	printf '%s=%q\n' "${variable}" "${!variable}"
done > /etc/inception-backup.env

mkdir -p /backups
printf '0 2 * * * root /usr/local/bin/backup.sh > /proc/1/fd/1 2> /proc/1/fd/2\n' > /etc/cron.d/inception-backup
chmod 644 /etc/cron.d/inception-backup
/usr/local/bin/backup.sh
exec cron -f