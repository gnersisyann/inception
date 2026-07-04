# =============================================================================
# Inception — project root Makefile
# Runs docker compose from srcs/
# =============================================================================

COMPOSE = docker compose -f srcs/docker-compose.yml

.PHONY: all build up down clean re logs

# Default: build images and start the stack
all: build up

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

clean: down
	$(COMPOSE) down --volumes --rmi local

re: clean all

logs:
	$(COMPOSE) logs -f

# LINUX_VM: before first `make up` on the VM, create data directories:
#   mkdir -p /home/ganersis/data/mariadb /home/ganersis/data/wordpress
# Then switch volumes in srcs/docker-compose.yml to bind mounts (see LINUX_VM comment there).
