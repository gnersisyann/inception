# =============================================================================
# Inception — project root Makefile
# Runs docker compose from srcs/
# =============================================================================

COMPOSE = docker compose --env-file srcs/.env -f srcs/docker-compose.yml

.PHONY: all setup build up down stop start clean re logs status check backup

# Default: build images and start the stack
all: up

setup:
	bash setup.sh "$(LOGIN)"

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d --build --wait --wait-timeout 300

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --rmi local

re: clean
	$(MAKE) all

logs:
	$(COMPOSE) logs -f

status:
	$(COMPOSE) ps

check:
	bash srcs/tools/verify.sh

backup:
	$(COMPOSE) exec -T backup /usr/local/bin/backup.sh
