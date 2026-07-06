# Developer Documentation

This guide explains how to set up, build, and maintain the Inception project from scratch.

## Prerequisites

- A Linux VM for final evaluation (Debian or Ubuntu recommended)
- Docker Engine + Docker Compose plugin
- `make`, `git`, `curl`
- macOS can be used for development; switch volume paths before evaluation (see [Data persistence](#data-persistence))

## Repository structure

```
inception/
├── Makefile
├── setup.sh                    # First-time machine setup
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                    # Passwords (not in Git)
│   ├── db_root_password.txt
│   ├── db_password.txt
│   ├── credentials.txt
│   └── wp_user_password.txt
└── srcs/
    ├── .env                    # Local config (not in Git)
    ├── .env.example            # Template for .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   └── tools/entrypoint.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/default.conf.template
        │   └── tools/entrypoint.sh
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf
            └── tools/entrypoint.sh
```

## Environment setup

### Quick setup (recommended)

```bash
git clone <your-repo-url> inception
cd inception
./setup.sh
make
```

`setup.sh` will:
- Install `git`, `make`, `curl`, `openssl`, and Docker (Debian only)
- Create `srcs/.env` from `.env.example` with project defaults
- Generate missing passwords in `secrets/`
- On Linux: create `/home/ganersis/data/` and patch `docker-compose.yml` bind mounts
- Add `ganersis.42.fr` to `/etc/hosts`

### Manual setup

### 1. Clone the repository

```bash
git clone <your-repo-url> inception
cd inception
```

### 2. Create configuration files

```bash
cp srcs/.env.example srcs/.env
```

Edit `srcs/.env` — example values:

```env
DOMAIN_NAME=ganersis.42.fr
CONTAINER_NGINX=nginx
CONTAINER_MARIADB=mariadb
CONTAINER_WORDPRESS=wordpress
DB_NAME=ganersis_db
DB_USER=ganersis_user
DB_HOST=mariadb
WP_TITLE=ganersis_blog
WP_ADMIN_USER=ganersis
WP_ADMIN_EMAIL=ganersis@student.42yerevan.am
WP_USER=ganersis_user
WP_USER_EMAIL=ganersis.user@student.42yerevan.am
```

### 3. Create secrets

Each file contains **one password on a single line** (no quotes, no spaces):

```bash
mkdir -p secrets
echo "your_root_password"     > secrets/db_root_password.txt
echo "your_db_password"       > secrets/db_password.txt
echo "your_admin_password"    > secrets/credentials.txt
echo "your_wp_user_password"  > secrets/wp_user_password.txt
echo "your_ftp_password"      > secrets/ftp_password.txt
chmod 600 secrets/*.txt
```

### 4. Configure the domain

Add to `/etc/hosts` on the machine that opens the browser:

```
<IP_OF_VM>  ganersis.42.fr
```

## Build and launch

```bash
make        # docker compose build + up -d
```

Individual steps:

```bash
make build  # Build mariadb, wordpress, nginx images
make up     # Start containers in background
```

## Managing containers and volumes

| Command | Action |
|---------|--------|
| `make` | Build and start |
| `make down` | Stop containers (data kept) |
| `make clean` | Stop + remove volumes + remove local images |
| `make re` | Clean slate and full restart |
| `make logs` | Stream logs from all services |

### Docker Compose equivalents

```bash
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs mariadb
docker compose -f srcs/docker-compose.yml restart wordpress
docker compose -f srcs/docker-compose.yml build nginx
```

### Rebuild a single service

```bash
docker compose -f srcs/docker-compose.yml build wordpress
docker compose -f srcs/docker-compose.yml up -d --force-recreate wordpress
```

## Data persistence

| Volume | Container path | Content |
|--------|----------------|---------|
| `mariadb_data` | `/var/lib/mysql` | MariaDB database files |
| `wordpress_data` | `/var/www/html` | WordPress installation and uploads |

### macOS (development)

Default named volumes in `docker-compose.yml` — no extra setup.

### Linux VM (evaluation)

Replace the `volumes:` section in `srcs/docker-compose.yml` with bind mounts (see `LINUX_VM` comment in that file):

```bash
mkdir -p /home/ganersis/data/mariadb /home/ganersis/data/wordpress
```

Data will then persist at:

```
/home/ganersis/data/mariadb/
/home/ganersis/data/wordpress/
```

## How secrets reach containers

Compose mounts secret files into `/run/secrets/`. Entrypoint scripts read them at startup:

| Secret file | Read by | Becomes |
|-------------|---------|---------|
| `db_root_password.txt` | mariadb entrypoint | `MYSQL_ROOT_PASSWORD` |
| `db_password.txt` | mariadb + wordpress | `MYSQL_PASSWORD` / `DB_PASSWORD` |
| `credentials.txt` | wordpress entrypoint | `WP_ADMIN_PASSWORD` |
| `wp_user_password.txt` | wordpress entrypoint | `WP_USER_PASSWORD` |

## Service details

### MariaDB

- Image: `mariadb:inception`
- Listens on `0.0.0.0:3306` inside the network
- First start: initializes database, creates user and schema
- Marker file `.inception_done` in the data directory prevents re-initialization

### WordPress

- Image: `wordpress:inception`
- PHP-FPM listens on `9000` (configured in `conf/www.conf`)
- Installs WordPress via WP-CLI on first start
- Creates two users: admin + author

### NGINX

- Image: `nginx:inception`
- Generates a self-signed TLS certificate for `DOMAIN_NAME`
- TLS 1.2 and 1.3 only, port 443
- Proxies PHP to `wordpress:9000` via FastCGI

## Common development workflow

```bash
# Edit a Dockerfile or config
vim srcs/requirements/nginx/conf/default.conf.template

# Rebuild and restart affected service
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d --force-recreate nginx

# Verify
curl -sk --resolve ganersis.42.fr:443:127.0.0.1 https://ganersis.42.fr/ -o /dev/null -w "%{http_code}\n"
```

## Before evaluation checklist

- [ ] Switch volumes to bind mounts under `/home/ganersis/data/`
- [ ] Update `/etc/hosts` on the evaluator's machine
- [ ] `make re` works on the VM without errors
- [ ] `https://ganersis.42.fr` loads WordPress
- [ ] `https://ganersis.42.fr/wp-admin/` accepts admin login
- [ ] Two WordPress users exist in the database
- [ ] No passwords in Git history
