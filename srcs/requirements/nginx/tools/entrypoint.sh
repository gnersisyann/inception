#!/bin/bash
set -e

# Expected env vars (set in docker-compose from .env):
#   DOMAIN_NAME, WORDPRESS_HOST (default: wordpress)

SSL_DIR="/etc/nginx/ssl"
WORDPRESS_HOST="${WORDPRESS_HOST:-wordpress}"

mkdir -p "${SSL_DIR}"

if [ ! -f "${SSL_DIR}/nginx.crt" ]; then
	echo "Generating self-signed TLS certificate for ${DOMAIN_NAME}..."
	openssl req -x509 -nodes -days 365 \
		-newkey rsa:2048 \
		-keyout "${SSL_DIR}/nginx.key" \
		-out "${SSL_DIR}/nginx.crt" \
		-subj "/CN=${DOMAIN_NAME}" \
		-addext "subjectAltName=DNS:${DOMAIN_NAME}"
fi

export DOMAIN_NAME WORDPRESS_HOST
envsubst '${DOMAIN_NAME} ${WORDPRESS_HOST}' \
	< /etc/nginx/templates/default.conf.template \
	> /etc/nginx/conf.d/default.conf

nginx -t
exec nginx -g 'daemon off;'
