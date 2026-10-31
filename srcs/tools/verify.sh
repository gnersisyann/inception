#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INCEPTION_LOGIN=verifyuser
source "${ROOT}/setup.sh"
PROJECT_ROOT="$(mktemp -d)"
ENV_FILE="${PROJECT_ROOT}/srcs/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/srcs/.env.example"
SECRETS_DIR="${PROJECT_ROOT}/secrets"
project="inception_verify_$$"
compose=(docker compose -p "${project}" --env-file "${ENV_FILE}" -f "${PROJECT_ROOT}/srcs/docker-compose.yml" -f "${PROJECT_ROOT}/srcs/verify.override.yml")

cleanup() {
	"${compose[@]}" down --volumes >/dev/null 2>&1 || true
	rm -rf "${PROJECT_ROOT}"
}
trap cleanup EXIT
trap 'exit 1' TERM INT
mkdir -p "${PROJECT_ROOT}/srcs"
cp -pR "${ROOT}/srcs/requirements" "${PROJECT_ROOT}/srcs/requirements"
cp "${ROOT}/srcs/docker-compose.yml" "${PROJECT_ROOT}/srcs/docker-compose.yml"
cp "${ROOT}/srcs/.env.example" "${ENV_EXAMPLE}"
setup_env
setup_secrets
for service in NGINX MARIADB WORDPRESS REDIS FTP STATIC ADMINER; do
	export "CONTAINER_${service}=${project}_${service,,}"
done
cat > "${PROJECT_ROOT}/srcs/verify.override.yml" <<'YAML'
services:
  nginx:
    ports: !override ["127.0.0.1::443"]
  static:
    ports: !override ["127.0.0.1::8080"]
  adminer:
    ports: !override ["127.0.0.1::8080"]
  ftp:
    ports: !override []
YAML

"${compose[@]}" config -q
"${compose[@]}" up -d --build --wait --wait-timeout 300
"${compose[@]}" exec -T wordpress wp --allow-root user list --fields=user_login,roles
"${compose[@]}" exec -T wordpress bash -c '
	wp --allow-root user list --format=json | php -r '\''
		$users = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
		if (count($users) !== 2) exit(1);
		$owners = array_filter($users, fn($user) => $user["roles"] === "administrator" && stripos($user["user_login"], "admin") === false);
		if (count($owners) !== 1) exit(1);
	'\'''
"${compose[@]}" exec -T wordpress bash -o pipefail -c 'wp --allow-root redis status | sed -n "/^Status:/p; /^Errors:/p"'
"${compose[@]}" exec -T wordpress bash -o pipefail -c 'wp --allow-root redis status | grep -q "^Status: Connected"'
port="$("${compose[@]}" port nginx 443 | sed 's/.*://')"
url="https://${DOMAIN}:${port}"
curl -fkSs --resolve "${DOMAIN}:${port}:127.0.0.1" "${url}/" >/dev/null
curl -fkSs --resolve "${DOMAIN}:${port}:127.0.0.1" "${url}/wp-login.php" >/dev/null
for protocol in 1.2 1.3; do
	"${compose[@]}" exec -T nginx bash -c 'curl -fkSs --tlsv"$1" --tls-max "$1" --resolve "${DOMAIN_NAME}:443:127.0.0.1" "https://${DOMAIN_NAME}/" >/dev/null' -- "${protocol}"
done
for protocol in 1.0 1.1; do
	if "${compose[@]}" exec -T nginx bash -c 'curl -fkSs --tlsv"$1" --tls-max "$1" --resolve "${DOMAIN_NAME}:443:127.0.0.1" "https://${DOMAIN_NAME}/" >/dev/null' -- "${protocol}" 2>/dev/null; then
		error "NGINX accepted TLS ${protocol}."
	fi
	flag="-tls1"
	[[ "${protocol}" == 1.1 ]] && flag="-tls1_1"
	"${compose[@]}" exec -T nginx bash -c 'openssl s_client "$1" -cipher "ALL:@SECLEVEL=0" -connect 127.0.0.1:443 -servername "$DOMAIN_NAME" </dev/null 2>&1 | grep -q "alert protocol version"' -- "${flag}"
done
for path in wp-config.php .env; do
	code="$(curl -ksS --resolve "${DOMAIN}:${port}:127.0.0.1" "${url}/${path}" -o /dev/null -w '%{http_code}')"
	[[ "${code}" == 403 ]] || error "NGINX did not protect ${path}."
done
for service in static adminer; do
	address="$("${compose[@]}" port "${service}" 8080)"
	curl -fSs "http://${address}/" >/dev/null
done
"${compose[@]}" exec -T wordpress bash -c 'read -r password; printf "inception verification\n" | curl -fsS --user "${FTP_USER}:${password}" -T - ftp://ftp/verify.txt' < "${SECRETS_DIR}/ftp_password.txt"
curl -fkSs --resolve "${DOMAIN}:${port}:127.0.0.1" "${url}/verify.txt" | grep -q 'inception verification'
"${compose[@]}" exec -T backup bash -c 'snapshot=$(find /backups -maxdepth 1 -type d -name "snapshot-*" | sort | tail -n 1); gzip -t "${snapshot}/database.sql.gz"; tar -tzf "${snapshot}/wordpress.tar.gz" >/dev/null'
"${compose[@]}" exec -T wordpress wp --allow-root option update inception_verify persistent_value
"${compose[@]}" exec -T backup /usr/local/bin/backup.sh
snapshot="$("${compose[@]}" exec -T backup bash -c 'find /backups -maxdepth 1 -type d -name "snapshot-*" | sort | tail -n 1')"
"${compose[@]}" cp "backup:${snapshot}" "${PROJECT_ROOT}/snapshot"
"${compose[@]}" exec -T wordpress wp --allow-root option update inception_verify changed_value
"${compose[@]}" exec -T wordpress rm /var/www/html/verify.txt
"${compose[@]}" stop nginx wordpress ftp backup
gzip -dc "${PROJECT_ROOT}/snapshot/database.sql.gz" \
	| "${compose[@]}" exec -T mariadb bash -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot'
"${compose[@]}" run --rm --no-deps -T --entrypoint tar wordpress \
	-xzf - -C /var/www/html < "${PROJECT_ROOT}/snapshot/wordpress.tar.gz"
"${compose[@]}" up -d --wait --wait-timeout 120
"${compose[@]}" exec -T wordpress wp --allow-root cache flush
"${compose[@]}" exec -T wordpress wp --allow-root option get inception_verify | grep -qx persistent_value
port="$("${compose[@]}" port nginx 443 | sed 's/.*://')"
url="https://${DOMAIN}:${port}"
curl -fkSs --resolve "${DOMAIN}:${port}:127.0.0.1" "${url}/verify.txt" | grep -q 'inception verification'
"${compose[@]}" exec -T nginx bash -c 'kill -QUIT 1'
for attempt in $(seq 1 30); do
	[[ "$(docker inspect "${CONTAINER_NGINX}" --format '{{.RestartCount}}')" -gt 0 ]] && break
	[[ "${attempt}" -lt 30 ]] || error "NGINX did not restart after its daemon exited."
	sleep 1
done
"${compose[@]}" up -d --wait --wait-timeout 120
[[ "$(docker inspect "${CONTAINER_NGINX}" --format '{{.RestartCount}}')" -gt 0 ]] || error "NGINX did not restart after a crash."
"${compose[@]}" down
"${compose[@]}" up -d --wait --wait-timeout 300
curl -fkSs --resolve "${DOMAIN}:$("${compose[@]}" port nginx 443 | sed 's/.*://'):127.0.0.1" "https://${DOMAIN}:$("${compose[@]}" port nginx 443 | sed 's/.*://')/verify.txt" | grep -q 'inception verification'
"${compose[@]}" exec -T wordpress wp --allow-root core is-installed
"${compose[@]}" exec -T wordpress wp --allow-root option get inception_verify | grep -qx persistent_value
"${compose[@]}" exec -T wordpress wp --allow-root option delete inception_verify
"${compose[@]}" exec -T wordpress rm /var/www/html/verify.txt
"${compose[@]}" ps
echo "PASS: eight services, WordPress users, Redis, HTTPS/TLS, protected files, FTP, backup restore, daemon restart and persistence."
echo "VM-only: confirm DockerRootDir, volume mountpoints, host DNS/firewall and reboot recovery."