#!/usr/bin/env bash
# =============================================================================
# Inception — first-time setup for a new machine
# Usage: ./setup.sh
# Tested on: Debian Bookworm (42 VM)
# =============================================================================

set -euo pipefail

LOGIN="ganersis"
DOMAIN="${LOGIN}.42.fr"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROJECT_ROOT}/srcs/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/srcs/.env.example"
COMPOSE_FILE="${PROJECT_ROOT}/srcs/docker-compose.yml"
SECRETS_DIR="${PROJECT_ROOT}/secrets"
DATA_DIR="/home/${LOGIN}/data"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || error "'$1' is required but not installed."
}

is_linux() {
	[[ "$(uname -s)" == "Linux" ]]
}

is_debian() {
	[[ -f /etc/debian_version ]]
}

has_sudo() {
	command -v sudo >/dev/null 2>&1
}

run_as_root() {
	if [[ "${EUID}" -eq 0 ]]; then
		"$@"
	elif has_sudo; then
		sudo "$@"
	else
		error "Root privileges required. Run as root or install sudo."
	fi
}

generate_password() {
	openssl rand -base64 16 | tr -d '/+=' | head -c 18
}

write_secret_if_missing() {
	local file="$1"
	if [[ ! -s "${file}" ]]; then
		generate_password > "${file}"
		info "Generated secret: ${file}"
	fi
}

# -----------------------------------------------------------------------------
# 1. Install system packages (Debian only)
# -----------------------------------------------------------------------------

install_system_packages() {
	if ! is_linux || ! is_debian; then
		warn "Skipping apt packages (not Debian Linux)."
		return
	fi

	info "Installing system packages..."
	run_as_root apt-get update -qq
	run_as_root apt-get install -y -qq \
		git make curl ca-certificates gnupg lsb-release openssl

	if ! command -v docker >/dev/null 2>&1; then
		info "Installing Docker..."
		run_as_root install -m 0755 -d /etc/apt/keyrings
		if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
			curl -fsSL https://download.docker.com/linux/debian/gpg \
				| run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
		fi

		if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
			echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
				| run_as_root tee /etc/apt/sources.list.d/docker.list > /dev/null
		fi

		run_as_root apt-get update -qq
		run_as_root apt-get install -y -qq \
			docker-ce docker-ce-cli containerd.io \
			docker-buildx-plugin docker-compose-plugin
	fi

	if [[ "${EUID}" -ne 0 ]] && ! groups "${USER}" | grep -q docker; then
		run_as_root usermod -aG docker "${USER}"
		warn "Added '${USER}' to docker group. Log out and back in if 'docker' fails without sudo."
	fi
}

# -----------------------------------------------------------------------------
# 2. Verify Docker
# -----------------------------------------------------------------------------

verify_docker() {
	need_cmd docker

	if ! docker info >/dev/null 2>&1; then
		if has_sudo && sudo docker info >/dev/null 2>&1; then
			warn "Docker works with sudo only. Run: newgrp docker  (or re-login)"
		else
			error "Docker is not running or not accessible."
		fi
	fi

	need_cmd docker
	docker compose version >/dev/null 2>&1 || error "docker compose plugin not found."
	info "Docker OK: $(docker compose version)"
}

# -----------------------------------------------------------------------------
# 3. Create .env
# -----------------------------------------------------------------------------

setup_env() {
	if [[ ! -f "${ENV_EXAMPLE}" ]]; then
		error "Missing ${ENV_EXAMPLE}"
	fi

	if [[ ! -f "${ENV_FILE}" ]]; then
		cp "${ENV_EXAMPLE}" "${ENV_FILE}"
		info "Created ${ENV_FILE} from example."
	fi

	# Fill empty values with project defaults (idempotent)
	local tmp
	tmp="$(mktemp)"
	while IFS= read -r line || [[ -n "${line}" ]]; do
		case "${line}" in
			DOMAIN_NAME=)           echo "DOMAIN_NAME=${DOMAIN}" ;;
			CONTAINER_NGINX=)       echo "CONTAINER_NGINX=nginx" ;;
			CONTAINER_MARIADB=)     echo "CONTAINER_MARIADB=mariadb" ;;
			CONTAINER_WORDPRESS=)   echo "CONTAINER_WORDPRESS=wordpress" ;;
			CONTAINER_REDIS=)       echo "CONTAINER_REDIS=redis" ;;
			REDIS_HOST=)            echo "REDIS_HOST=redis" ;;
			CONTAINER_FTP=)         echo "CONTAINER_FTP=ftp" ;;
			FTP_USER=)              echo "FTP_USER=${LOGIN}_ftp" ;;
			CONTAINER_STATIC=)      echo "CONTAINER_STATIC=static" ;;
			STATIC_PORT=)           echo "STATIC_PORT=8080" ;;
			CONTAINER_ADMINER=)    echo "CONTAINER_ADMINER=adminer" ;;
			ADMINER_PORT=)          echo "ADMINER_PORT=8081" ;;
			DB_NAME=)               echo "DB_NAME=${LOGIN}_db" ;;
			DB_USER=)               echo "DB_USER=${LOGIN}_user" ;;
			DB_HOST=)               echo "DB_HOST=mariadb" ;;
			WP_TITLE=)              echo "WP_TITLE=${LOGIN}_blog" ;;
			WP_ADMIN_USER=)         echo "WP_ADMIN_USER=${LOGIN}" ;;
			WP_ADMIN_EMAIL=)        echo "WP_ADMIN_EMAIL=${LOGIN}@student.42yerevan.am" ;;
			WP_USER=)               echo "WP_USER=${LOGIN}_user" ;;
			WP_USER_EMAIL=)         echo "WP_USER_EMAIL=${LOGIN}.user@student.42yerevan.am" ;;
			*)                      echo "${line}" ;;
		esac
	done < "${ENV_FILE}" > "${tmp}"
	mv "${tmp}" "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"
	info "Configured ${ENV_FILE}"
}

# -----------------------------------------------------------------------------
# 4. Create secrets
# -----------------------------------------------------------------------------

setup_secrets() {
	mkdir -p "${SECRETS_DIR}"
	write_secret_if_missing "${SECRETS_DIR}/db_root_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/db_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/credentials.txt"
	write_secret_if_missing "${SECRETS_DIR}/ftp_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/wp_user_password.txt"
	chmod 600 "${SECRETS_DIR}"/*.txt 2>/dev/null || true
	info "Secrets ready in ${SECRETS_DIR}/"
}

# -----------------------------------------------------------------------------
# 5. Linux VM: bind mounts + data directories
# -----------------------------------------------------------------------------

setup_linux_volumes() {
	if ! is_linux; then
		warn "Skipping Linux bind mounts (macOS uses Docker named volumes)."
		return
	fi

	info "Creating data directories..."
	run_as_root mkdir -p "${DATA_DIR}/mariadb" "${DATA_DIR}/wordpress"
	run_as_root chown -R "${USER}:${USER}" "/home/${LOGIN}/data" 2>/dev/null \
		|| run_as_root chown -R "${USER}" "/home/${LOGIN}/data"

	if grep -q "device: ${DATA_DIR}/mariadb" "${COMPOSE_FILE}"; then
		info "docker-compose.yml already has Linux bind mounts."
		return
	fi

	info "Patching docker-compose.yml for Linux bind mounts..."
	local tmp
	tmp="$(mktemp)"
	awk -v data="${DATA_DIR}" '
		/^volumes:$/ && !done {
			print "volumes:"
			print "  mariadb_data:"
			print "    driver: local"
			print "    driver_opts:"
			print "      type: none"
			print "      o: bind"
			print "      device: " data "/mariadb"
			print "  wordpress_data:"
			print "    driver: local"
			print "    driver_opts:"
			print "      type: none"
			print "      o: bind"
			print "      device: " data "/wordpress"
			skip = 1
			done = 1
			next
		}
		skip && /^[^ ]/ { skip = 0 }
		skip { next }
		{ print }
	' "${COMPOSE_FILE}" > "${tmp}"
	mv "${tmp}" "${COMPOSE_FILE}"
	info "Bind mounts set to ${DATA_DIR}/"
}

# -----------------------------------------------------------------------------
# 6. /etc/hosts
# -----------------------------------------------------------------------------

setup_hosts() {
	local ip="127.0.0.1"
	if is_linux; then
		ip="$(hostname -I 2>/dev/null | awk "{print \$1}")"
		[[ -z "${ip}" ]] && ip="127.0.0.1"
	fi

	if grep -q "${DOMAIN}" /etc/hosts 2>/dev/null; then
		info "/etc/hosts already has ${DOMAIN}"
		return
	fi

	info "Adding ${DOMAIN} -> ${ip} to /etc/hosts"
	echo "${ip}  ${DOMAIN}" | run_as_root tee -a /etc/hosts > /dev/null
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
	echo "============================================"
	echo " Inception setup — login: ${LOGIN}"
	echo "============================================"

	cd "${PROJECT_ROOT}"

	install_system_packages
	verify_docker
	setup_env
	setup_secrets
	setup_linux_volumes
	setup_hosts

	echo ""
	echo "============================================"
	echo " Setup complete!"
	echo "============================================"
	echo ""
	echo "Next steps:"
	echo "  cd ${PROJECT_ROOT}"
	echo "  make"
	echo ""
	echo "Then open:"
	echo "  https://${DOMAIN}"
	echo "  http://localhost:8080   (static site)"
	echo "  http://localhost:8081   (adminer)"
	echo ""
	echo "Credentials:"
	echo "  secrets/          — all passwords (DB, WP admin, WP user, FTP)"
	echo "  srcs/.env         — non-sensitive config"
	echo ""
	if is_linux && ! groups "${USER}" 2>/dev/null | grep -q docker; then
		warn "Run 'newgrp docker' or re-login before 'make' if docker permission denied."
	fi
}

main "$@"
