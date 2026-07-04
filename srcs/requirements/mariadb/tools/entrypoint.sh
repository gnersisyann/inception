#!/bin/bash
set -e

DATADIR="/var/lib/mysql"

# Expected env vars (set in docker-compose from .env + secrets):
#   MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

if [ -f /run/secrets/db_root_password ]; then
	MYSQL_ROOT_PASSWORD="$(tr -d '\n' < /run/secrets/db_root_password)"
fi

if [ -f /run/secrets/db_password ]; then
	MYSQL_PASSWORD="$(tr -d '\n' < /run/secrets/db_password)"
fi

if [ -z "${MYSQL_ROOT_PASSWORD}" ] || [ -z "${MYSQL_DATABASE}" ] || [ -z "${MYSQL_USER}" ] || [ -z "${MYSQL_PASSWORD}" ]; then
	echo "MariaDB environment is not fully configured."
	exit 1
fi

if [ ! -d "${DATADIR}/mysql" ]; then
	echo "Initializing MariaDB data directory..."

	mariadb-install-db --user=mysql --datadir="${DATADIR}" > /dev/null

	tfile="$(mktemp)"
	cat > "${tfile}" <<-EOSQL
		USE mysql;
		FLUSH PRIVILEGES;

		ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';

		DELETE FROM mysql.user WHERE User = '';
		DROP DATABASE IF EXISTS test;
		DELETE FROM mysql.db WHERE Db = 'test' OR Db LIKE 'test\\_%';

		CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
		CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
		GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

		FLUSH PRIVILEGES;
	EOSQL

	mysqld --user=mysql --bootstrap < "${tfile}"
	rm -f "${tfile}"
fi

exec mysqld --user=mysql --datadir="${DATADIR}" --bind-address=0.0.0.0
