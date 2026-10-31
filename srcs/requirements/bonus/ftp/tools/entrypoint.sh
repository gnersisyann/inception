#!/bin/bash
set -euo pipefail

# Expected env vars: FTP_USER
# Expected secret: /run/secrets/ftp_password

if [ -f /run/secrets/ftp_password ]; then
	FTP_PASSWORD="$(tr -d '\n' < /run/secrets/ftp_password)"
fi

if [ -z "${FTP_USER:-}" ] || [ -z "${FTP_PASSWORD:-}" ] || [ -z "${FTP_PASV_ADDRESS:-}" ]; then
	echo "FTP credentials are not configured."
	exit 1
fi

[[ "${FTP_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "Invalid FTP user."; exit 1; }
[[ "${FTP_PASV_ADDRESS}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
	|| { echo "FTP_PASV_ADDRESS must be the VM IPv4 address."; exit 1; }
if ! id "${FTP_USER}" >/dev/null 2>&1; then
	useradd -M -d /var/www/html -s /usr/sbin/nologin "${FTP_USER}"
	usermod -aG www-data "${FTP_USER}"
fi
echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
grep -qxF /usr/sbin/nologin /etc/shells || echo /usr/sbin/nologin >> /etc/shells
printf '%s\n' "${FTP_USER}" > /etc/vsftpd.user_list
sed -i '/^pasv_address=/d' /etc/vsftpd.conf
printf '\npasv_address=%s\n' "${FTP_PASV_ADDRESS}" >> /etc/vsftpd.conf

find /var/www/html -type d -exec chmod g+ws {} +
find /var/www/html -type f ! -name wp-config.php -exec chmod g+w {} +

exec /usr/sbin/vsftpd /etc/vsftpd.conf
