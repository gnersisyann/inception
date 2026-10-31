#!/bin/bash
set -euo pipefail
umask 077

source /etc/inception-backup.env
exec 9>/backups/.backup.lock
flock -n 9 || { echo "Another backup is running."; exit 1; }
snapshot="/backups/snapshot-$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d /backups/.pending-XXXXXX)"
trap 'rm -rf "${staging}"' EXIT

MYSQL_PWD="$(tr -d '\n' < /run/secrets/db_password)" \
	mariadb-dump --host="${DB_HOST}" --user="${DB_USER}" \
	--single-transaction --skip-lock-tables --databases "${DB_NAME}" \
	| gzip > "${staging}/database.sql.gz"
tar -czf "${staging}/wordpress.tar.gz" -C /var/www/html .
mv "${staging}" "${snapshot}"
find /backups -maxdepth 1 -type d -name 'snapshot-*' -mtime +7 -exec rm -rf {} +
echo "Backup complete: ${snapshot}"