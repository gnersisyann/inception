#!/bin/bash
set -euo pipefail

DATADIR="/var/lib/mysql"
INIT_MARKER="${DATADIR}/.inception_done"

# Expected env vars (set in docker-compose from .env + secrets):
#   MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

if [ -f /run/secrets/db_root_password ]; then
	MYSQL_ROOT_PASSWORD="$(tr -d '\n' < /run/secrets/db_root_password)"
fi

if [ -f /run/secrets/db_password ]; then
	MYSQL_PASSWORD="$(tr -d '\n' < /run/secrets/db_password)"
fi

if [ -z "${MYSQL_ROOT_PASSWORD:-}" ] || [ -z "${MYSQL_DATABASE:-}" ] || [ -z "${MYSQL_USER:-}" ] || [ -z "${MYSQL_PASSWORD:-}" ]; then
	echo "MariaDB environment is not fully configured."
	exit 1
fi

[[ "${MYSQL_DATABASE}" =~ ^[a-zA-Z0-9_]+$ && "${MYSQL_USER}" =~ ^[a-zA-Z0-9_]+$ && "${MYSQL_USER}" != root ]] \
	|| { echo "Invalid database name or database user."; exit 1; }
mkdir -p /var/run/mysqld "${DATADIR}"
chown -R mysql:mysql /var/run/mysqld "${DATADIR}"

if [ ! -f "${INIT_MARKER}" ]; then
	echo "Initializing MariaDB data directory..."

	if [ -d "${DATADIR}/mysql" ]; then
		echo "Existing database has no initialization marker. Refusing to erase it; inspect or restore a backup."
		exit 1
	fi

	mariadb-install-db --user=mysql --datadir="${DATADIR}" > /dev/null

	mysqld --user=mysql --datadir="${DATADIR}" --skip-networking &
	pid=$!
	trap 'kill "${pid}" 2>/dev/null || true; wait "${pid}" 2>/dev/null || true' EXIT
	trap 'exit 1' TERM INT

	for attempt in $(seq 1 30); do
		if mariadb -uroot -e "SELECT 1;" >/dev/null 2>&1; then
			break
		fi
		if [ "${attempt}" -eq 30 ]; then
			echo "MariaDB failed to start for initialization."
			kill "${pid}"
			exit 1
		fi
		sleep 1
	done

	root_password_sql="${MYSQL_ROOT_PASSWORD//\'/\'\'}"
	password_sql="${MYSQL_PASSWORD//\'/\'\'}"
	mariadb -uroot <<-EOSQL
		SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES';
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_password_sql}';
		DELETE FROM mysql.user WHERE User = '';
		DROP DATABASE IF EXISTS test;
		DELETE FROM mysql.db WHERE Db = 'test' OR Db LIKE 'test\\_%';
		CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
		CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${password_sql}';
		GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
		FLUSH PRIVILEGES;
	EOSQL

	kill "${pid}"
	wait "${pid}" 2>/dev/null || true
	trap - EXIT TERM INT

	touch "${INIT_MARKER}"
fi

exec mysqld --user=mysql --datadir="${DATADIR}" --bind-address=0.0.0.0
