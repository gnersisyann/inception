#!/bin/bash
set -e

WP_PATH="/var/www/html"
WP_CLI="wp --path=${WP_PATH} --allow-root"

# Expected env vars (set in docker-compose from .env + secrets):
#   DOMAIN_NAME, DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
#   WP_ADMIN_USER, WP_ADMIN_EMAIL, WP_ADMIN_PASSWORD
#   WP_USER, WP_USER_EMAIL, WP_USER_PASSWORD
#   WP_TITLE (optional)

if [ -f /run/secrets/db_password ]; then
	DB_PASSWORD="$(tr -d '\n' < /run/secrets/db_password)"
fi

if [ -f /run/secrets/credentials ]; then
	WP_ADMIN_PASSWORD="$(tr -d '\n' < /run/secrets/credentials)"
fi

if [ -z "${DB_PASSWORD}" ] || [ -z "${WP_ADMIN_PASSWORD}" ]; then
	echo "WordPress secrets are not fully configured."
	exit 1
fi

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

if [ ! -f "${WP_PATH}/wp-config.php" ]; then
	echo "Installing WordPress..."

	${WP_CLI} core download --locale=en_US

	${WP_CLI} config create \
		--dbname="${DB_NAME}" \
		--dbuser="${DB_USER}" \
		--dbpass="${DB_PASSWORD}" \
		--dbhost="${DB_HOST}" \
		--skip-check

	${WP_CLI} core install \
		--url="https://${DOMAIN_NAME}" \
		--title="${WP_TITLE:-ganersis_blog}" \
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

if ${WP_CLI} core is-installed >/dev/null 2>&1; then
	if redis-cli -h "${REDIS_HOST}" ping 2>/dev/null | grep -q PONG; then
		if ! ${WP_CLI} plugin is-active redis-cache >/dev/null 2>&1; then
			${WP_CLI} plugin install redis-cache --activate
		fi

		${WP_CLI} config set WP_REDIS_HOST "${REDIS_HOST}" --type=constant
		${WP_CLI} config set WP_REDIS_PORT 6379 --type=constant --raw

		if ! ${WP_CLI} redis status 2>/dev/null | grep -qi "connected"; then
			${WP_CLI} redis enable
		fi
	else
		echo "Redis is not available — skipping object cache setup."
	fi
fi

chown -R www-data:www-data "${WP_PATH}"

exec php-fpm8.2 -F
