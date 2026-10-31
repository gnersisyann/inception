#!/bin/bash
set -euo pipefail

WP_PATH="/var/www/html"
WP_CLI="wp --path=${WP_PATH} --allow-root"

# Expected env vars (set in docker-compose from .env + secrets):
#   DOMAIN_NAME, DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
#   WP_ADMIN_USER, WP_ADMIN_EMAIL, WP_ADMIN_PASSWORD
#   WP_USER, WP_USER_EMAIL, WP_USER_PASSWORD (from secrets/wp_user_password.txt)
#   WP_TITLE (optional)

if [ -f /run/secrets/db_password ]; then
	DB_PASSWORD="$(tr -d '\n' < /run/secrets/db_password)"
fi

if [ -f /run/secrets/credentials ]; then
	WP_ADMIN_PASSWORD="$(tr -d '\n' < /run/secrets/credentials)"
fi

if [ -f /run/secrets/wp_user_password ]; then
	WP_USER_PASSWORD="$(tr -d '\n' < /run/secrets/wp_user_password)"
fi

if [ -z "${DB_PASSWORD:-}" ] || [ -z "${WP_ADMIN_PASSWORD:-}" ] || [ -z "${WP_USER_PASSWORD:-}" ]; then
	echo "WordPress secrets are not fully configured."
	exit 1
fi

for variable in DOMAIN_NAME DB_HOST DB_NAME DB_USER WP_ADMIN_USER WP_ADMIN_EMAIL WP_USER WP_USER_EMAIL; do
	[[ -n "${!variable:-}" ]] || { echo "Missing ${variable}."; exit 1; }
done
[[ "${WP_ADMIN_USER,,}" != *admin* && "${WP_ADMIN_USER}" != "${WP_USER}" ]] \
	|| { echo "Administrator login must not contain admin and must differ from the second user."; exit 1; }

echo "Waiting for MariaDB..."
retries=30
until mariadb -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; do
	retries=$((retries - 1))
	if [ "${retries}" -le 0 ]; then
		echo "MariaDB is not available."
		exit 1
	fi
	sleep 2
done

if [ ! -f "${WP_PATH}/wp-load.php" ]; then
	${WP_CLI} core download --locale=en_US --version=7.1.4 --force
fi

if [ ! -f "${WP_PATH}/wp-config.php" ]; then
	${WP_CLI} config create \
		--dbname="${DB_NAME}" \
		--dbuser="${DB_USER}" \
		--dbpass="${DB_PASSWORD}" \
		--dbhost="${DB_HOST}" \
		--skip-check
fi

if ! ${WP_CLI} core is-installed >/dev/null 2>&1; then
	echo "Installing WordPress database..."
	${WP_CLI} core install \
		--url="https://${DOMAIN_NAME}" \
		--title="${WP_TITLE:-Inception}" \
		--admin_user="${WP_ADMIN_USER}" \
		--admin_password="${WP_ADMIN_PASSWORD}" \
		--admin_email="${WP_ADMIN_EMAIL}" \
		--skip-email
fi

if ! ${WP_CLI} user get "${WP_USER}" >/dev/null 2>&1; then
	if [ -z "${WP_USER_PASSWORD}" ]; then
		echo "WP_USER_PASSWORD is not set."
		exit 1
	fi

	${WP_CLI} user create "${WP_USER}" "${WP_USER_EMAIL}" \
		--role=author \
		--user_pass="${WP_USER_PASSWORD}"
fi

REDIS_HOST="${REDIS_HOST:-redis}"

retries=30
until redis-cli -h "${REDIS_HOST}" ping 2>/dev/null | grep -q PONG; do
	retries=$((retries - 1))
	[[ "${retries}" -gt 0 ]] || { echo "Redis is not available."; exit 1; }
	sleep 2
done
if ! ${WP_CLI} plugin is-installed redis-cache; then
	${WP_CLI} plugin install redis-cache --version=2.5.4
fi
${WP_CLI} plugin activate redis-cache
${WP_CLI} config set WP_REDIS_HOST "${REDIS_HOST}" --type=constant
${WP_CLI} config set WP_REDIS_PORT 6379 --type=constant --raw
${WP_CLI} redis enable
${WP_CLI} redis status

chown -R www-data:www-data "${WP_PATH}"
chmod 640 "${WP_PATH}/wp-config.php"

exec php-fpm8.2 -F
