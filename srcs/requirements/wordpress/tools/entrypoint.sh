#!/bin/bash
set -e

WP_PATH="/var/www/html"
WP_CLI="wp --path=${WP_PATH} --allow-root"

# Expected env vars (set in docker-compose from .env + secrets):
#   DOMAIN_NAME, DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
#   WP_ADMIN_USER, WP_ADMIN_EMAIL, WP_ADMIN_PASSWORD
#   WP_USER, WP_USER_EMAIL, WP_USER_PASSWORD
#   WP_TITLE (optional)

echo "Waiting for MariaDB..."
retries=30
until mariadb-admin ping -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
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

	if [ -z "${WP_USER_PASSWORD}" ]; then
		echo "WP_USER_PASSWORD is not set."
		exit 1
	fi

	${WP_CLI} user create "${WP_USER}" "${WP_USER_EMAIL}" \
		--role=author \
		--user_pass="${WP_USER_PASSWORD}" \
		--skip-email
fi

chown -R www-data:www-data "${WP_PATH}"

exec php-fpm8.2 -F
