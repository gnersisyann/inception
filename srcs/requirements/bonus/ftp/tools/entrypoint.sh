#!/bin/bash
set -e

# Expected env vars: FTP_USER
# Expected secret: /run/secrets/ftp_password

if [ -f /run/secrets/ftp_password ]; then
	FTP_PASSWORD="$(tr -d '\n' < /run/secrets/ftp_password)"
fi

if [ -z "${FTP_USER}" ] || [ -z "${FTP_PASSWORD}" ]; then
	echo "FTP credentials are not configured."
	exit 1
fi

if ! id "${FTP_USER}" >/dev/null 2>&1; then
	useradd -m -d /var/www/html -s /usr/sbin/nologin "${FTP_USER}"
	echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
	usermod -aG www-data "${FTP_USER}"
fi

chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html

exec /usr/sbin/vsftpd /etc/vsftpd.conf
