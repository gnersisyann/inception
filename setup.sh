#!/usr/bin/env bash
# =============================================================================
# Inception — first-time setup for a new machine
# Usage: ./setup.sh <42-login>
# Target: Debian 13 VM; containers use Debian 12 (Bookworm).
# =============================================================================

set -euo pipefail
umask 077

LOGIN="${1:-${INCEPTION_LOGIN:-}}"
DOMAIN="${LOGIN}.42.fr"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROJECT_ROOT}/srcs/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/srcs/.env.example"
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
	openssl rand -hex 24
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
		git make curl ca-certificates gnupg lsb-release openssl jq

	if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
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

	run_as_root systemctl enable --now docker
	local operator="${SUDO_USER:-${USER}}"
	if [[ "${operator}" != root ]] && ! id -nG "${operator}" | tr ' ' '\n' | grep -qx docker; then
		run_as_root usermod -aG docker "${operator}"
		warn "Added '${operator}' to docker group. Log out and back in before running make."
	fi
}

# -----------------------------------------------------------------------------
# 2. Verify Docker
# -----------------------------------------------------------------------------

verify_docker() {
	need_cmd docker

	if ! docker info >/dev/null 2>&1; then
		if run_as_root docker info >/dev/null 2>&1; then
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
	local vm_ip="${INCEPTION_VM_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
	vm_ip="${vm_ip:-127.0.0.1}"
	while IFS= read -r line || [[ -n "${line}" ]]; do
		case "${line}" in
			LOGIN=)                echo "LOGIN=${LOGIN}" ;;
			DOMAIN_NAME=)           echo "DOMAIN_NAME=${DOMAIN}" ;;
			CONTAINER_NGINX=)       echo "CONTAINER_NGINX=nginx" ;;
			CONTAINER_MARIADB=)     echo "CONTAINER_MARIADB=mariadb" ;;
			CONTAINER_WORDPRESS=)   echo "CONTAINER_WORDPRESS=wordpress" ;;
			CONTAINER_REDIS=)       echo "CONTAINER_REDIS=redis" ;;
			REDIS_HOST=)            echo "REDIS_HOST=redis" ;;
			CONTAINER_FTP=)         echo "CONTAINER_FTP=ftp" ;;
			FTP_USER=)              echo "FTP_USER=${LOGIN}_ftp" ;;
			FTP_PASV_ADDRESS=)      echo "FTP_PASV_ADDRESS=${vm_ip}" ;;
			CONTAINER_STATIC=)      echo "CONTAINER_STATIC=static" ;;
			STATIC_PORT=)           echo "STATIC_PORT=8080" ;;
			CONTAINER_ADMINER=)    echo "CONTAINER_ADMINER=adminer" ;;
			ADMINER_PORT=)          echo "ADMINER_PORT=8081" ;;
			DB_NAME=)               echo "DB_NAME=${LOGIN}_db" ;;
			DB_USER=)               echo "DB_USER=${LOGIN}_user" ;;
			DB_HOST=)               echo "DB_HOST=mariadb" ;;
			WP_TITLE=)              echo "WP_TITLE=${LOGIN}_blog" ;;
			WP_ADMIN_USER=)         echo "WP_ADMIN_USER=site_owner" ;;
			WP_ADMIN_EMAIL=)        echo "WP_ADMIN_EMAIL=${LOGIN}@student.42.fr" ;;
			WP_USER=)               echo "WP_USER=${LOGIN}_user" ;;
			WP_USER_EMAIL=)         echo "WP_USER_EMAIL=${LOGIN}.user@student.42.fr" ;;
			*)                      echo "${line}" ;;
		esac
	done < "${ENV_FILE}" > "${tmp}"
	mv "${tmp}" "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"
	grep -qxF "DOMAIN_NAME=${DOMAIN}" "${ENV_FILE}" \
		|| error "Existing DOMAIN_NAME differs from ${DOMAIN}. Use the original login or edit .env explicitly."
	info "Configured ${ENV_FILE}"
}

# -----------------------------------------------------------------------------
# 4. Create secrets
# -----------------------------------------------------------------------------

setup_secrets() {
	mkdir -p "${SECRETS_DIR}"
	chmod 700 "${SECRETS_DIR}"
	write_secret_if_missing "${SECRETS_DIR}/db_root_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/db_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/credentials.txt"
	write_secret_if_missing "${SECRETS_DIR}/ftp_password.txt"
	write_secret_if_missing "${SECRETS_DIR}/wp_user_password.txt"
	chmod 600 "${SECRETS_DIR}"/*.txt 2>/dev/null || true
	info "Secrets ready in ${SECRETS_DIR}/"
}

# -----------------------------------------------------------------------------
# 5. Linux VM: Docker-managed named volumes under the learner's data directory
# -----------------------------------------------------------------------------

setup_linux_volumes() {
	if ! is_linux; then
		warn "The required volume location must be configured on a Linux VM."
		return
	fi

	local target="${DATA_DIR}/docker"
	local current
	current="$(run_as_root docker info --format '{{.DockerRootDir}}')"
	if [[ "${current}" == "${target}" ]]; then
		info "Docker named volumes already use ${target}/volumes."
		return
	fi

	if [[ -n "$(run_as_root docker ps -aq)$(run_as_root docker image ls -q)$(run_as_root docker volume ls -q)" ]]; then
		error "Docker already contains data. Back up and migrate it before changing data-root to ${target}."
	fi
	need_cmd jq
	local tmp
	tmp="$(mktemp)"
	if [[ -f /etc/docker/daemon.json ]]; then
		run_as_root jq --arg target "${target}" '. + {"data-root": $target}' /etc/docker/daemon.json > "${tmp}"
	else
		jq -n --arg target "${target}" '{"data-root": $target}' > "${tmp}"
	fi
	run_as_root dockerd --validate --config-file "${tmp}"
	run_as_root mkdir -p /etc/docker "${target}"
	run_as_root install -m 0644 "${tmp}" /etc/docker/daemon.json
	rm -f "${tmp}"
	run_as_root systemctl restart docker
	[[ "$(run_as_root docker info --format '{{.DockerRootDir}}')" == "${target}" ]] \
		|| error "Docker data-root did not change to ${target}."
	info "Named volumes will be stored in ${target}/volumes; no bind mounts are used."
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

	if awk -v domain="${DOMAIN}" '{for (field=2; field<=NF; field++) if ($field == domain) found=1} END {exit !found}' /etc/hosts; then
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
	[[ "${LOGIN}" =~ ^[a-z][a-z0-9_]{0,30}$ ]] || error "Usage: ./setup.sh <42-login> (lowercase letters, digits, underscores)."
	if ! is_linux || ! is_debian; then
		error "Run setup inside your Debian Linux VM, not on macOS."
	fi
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
	docker compose --env-file "${ENV_FILE}" -f srcs/docker-compose.yml config -q

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
	if ! docker info >/dev/null 2>&1; then
		warn "Log out and back in before make, or run sudo make."
	fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
