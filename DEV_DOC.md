# Developer Documentation

This guide explains how to set up, build, and maintain the Inception project from scratch.

## Prerequisites

- A fresh Debian 13 Linux VM for final evaluation, with root/sudo access
- Docker Engine + Docker Compose plugin v2.24.4 or newer
- Bash, `make`, `git`, `curl`, `openssl`, `jq` (installed by setup)
- macOS Docker Desktop can run `make check`, but cannot validate the required VM paths or Linux bootstrap

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
│   ├── wp_user_password.txt
│   └── ftp_password.txt
└── srcs/
    ├── .env                    # Local config (not in Git)
    ├── .env.example            # Template for .env
    ├── docker-compose.yml
    ├── tools/verify.sh          # Isolated integration check
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

The five additional services are under `srcs/requirements/bonus/`: `redis`, `ftp`, `static`, `adminer` and `backup`, each with its own Dockerfile. All service images derive from Debian 12 Bookworm, the penultimate stable Debian release while Debian 13 is current.

## Environment setup

### Quick setup (recommended)

```bash
git clone <your-repo-url> inception
cd inception
bash setup.sh ganersis  # Replace with your actual 42 login
# Log out/in if setup added your account to the docker group.
make
```

`setup.sh` will:
- Install `git`, `make`, `curl`, `openssl`, and Docker (Debian only)
- Create `srcs/.env` from `.env.example` with project defaults
- Generate missing passwords in `secrets/`
- Configure Docker `data-root` as `/home/<login>/data/docker`, preserving other daemon settings
- Add `ganersis.42.fr` to `/etc/hosts`

Alternatively, after installing `make`, use `make setup LOGIN=ganersis`. The script is idempotent: existing configuration values and nonempty secrets are preserved. It rejects a mismatched existing domain and refuses a data-root change if Docker already has containers, images or volumes. Stop and plan a backup/migration for an existing Docker installation; setup does not move or delete its data.

For a minimal Debian installation without Git or sudo, use `su -` to install `git sudo`, run `usermod -aG sudo <linux-user>`, and log in again. Setup must run inside the VM, not on macOS. With NAT, configure forwarding for 443 and the required bonus ports; bridged networking is simpler. Set `INCEPTION_VM_IP=<reachable-IPv4>` when running setup if automatic address detection selects the wrong interface.

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
LOGIN=ganersis
CONTAINER_NGINX=nginx
CONTAINER_MARIADB=mariadb
CONTAINER_WORDPRESS=wordpress
DB_NAME=ganersis_db
DB_USER=ganersis_user
DB_HOST=mariadb
WP_TITLE=ganersis_blog
WP_ADMIN_USER=site_owner
WP_ADMIN_EMAIL=ganersis@student.42yerevan.am
WP_USER=ganersis_user
WP_USER_EMAIL=ganersis.user@student.42yerevan.am
CONTAINER_REDIS=redis
REDIS_HOST=redis
CONTAINER_FTP=ftp
FTP_USER=ganersis_ftp
FTP_PASV_ADDRESS=<VM_IPv4>
CONTAINER_STATIC=static
STATIC_PORT=8080
CONTAINER_ADMINER=adminer
ADMINER_PORT=8081
```

### 3. Create secrets

Each file contains **one password on a single line** (no quotes, no spaces):

```bash
mkdir -p secrets
umask 077
for name in db_root_password db_password credentials wp_user_password ftp_password; do
    test -s "secrets/${name}.txt" || openssl rand -hex 24 > "secrets/${name}.txt"
done
chmod 700 secrets
chmod 600 secrets/*.txt
```

### 4. Configure the domain

Add to `/etc/hosts` on the machine that opens the browser:

```
<IP_OF_VM>  ganersis.42.fr
```

## Build and launch

```bash
make        # docker compose up -d --build --wait --wait-timeout 300
```

Individual steps:

```bash
make build  # Build all eight service images
make up     # Build and start in background, wait for readiness
```

## Managing containers and volumes

| Command | Action |
|---------|--------|
| `make` | Build and start |
| `make down` | Stop containers (data kept) |
| `make stop` / `make start` | Stop/start existing containers |
| `make clean` | Remove containers/network/local images, retain volumes |
| `make re` | Rebuild and recreate, retain data |
| `make logs` | Stream logs from all services |
| `make status` | Show running services |
| `make backup` | Create a new database/files snapshot |
| `make check` | Build and test a separate project, delete only its test volumes |

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
| `backup_data` | `/backups` | Compressed database and website snapshots |

### macOS (development)

Default named volumes in `docker-compose.yml` — no extra setup.

### Linux VM (evaluation)

Keep the named volumes in Compose unchanged. Setup merges this setting into `/etc/docker/daemon.json` and restarts Docker:

```json
{"data-root": "/home/ganersis/data/docker"}
```

This is daemon-wide configuration. It relocates Docker-managed storage, not just this project's volumes. Actual paths include the Compose project prefix:

```
/home/ganersis/data/docker/volumes/inception_mariadb_data/_data/
/home/ganersis/data/docker/volumes/inception_wordpress_data/_data/
/home/ganersis/data/docker/volumes/inception_backup_data/_data/
```

Inspect, rather than assuming a project prefix:

```bash
docker info --format '{{.DockerRootDir}}'
docker volume ls
docker volume inspect inception_mariadb_data inception_wordpress_data inception_backup_data
docker inspect mariadb --format '{{json .Mounts}}'
```

The persistent mounts must have `Type: volume`, no bind driver options, and mountpoints under `/home/<login>/data/`. `make down`, `clean` and `re` preserve volumes. `docker compose down --volumes` is destructive and is deliberately not a routine Makefile target. Never use it to troubleshoot valuable data.

## How secrets reach containers

Compose mounts secret files into `/run/secrets/`. Entrypoint scripts read them at startup:

| Secret file | Read by | Becomes |
|-------------|---------|---------|
| `db_root_password.txt` | mariadb entrypoint | `MYSQL_ROOT_PASSWORD` |
| `db_password.txt` | mariadb + wordpress + backup | Database access |
| `credentials.txt` | wordpress entrypoint | `WP_ADMIN_PASSWORD` |
| `wp_user_password.txt` | wordpress entrypoint | `WP_USER_PASSWORD` |
| `ftp_password.txt` | ftp entrypoint | `FTP_PASSWORD` |

Compose secrets are mounted files, not an encrypted vault. Protect the host secret files and backups. Password changes for existing MariaDB/WordPress accounts require an application/database update as well as updating the secret; startup does not silently reset them. FTP applies its secret on each start.

## Service details

### MariaDB

- Image: `mariadb:inception`
- Listens on `0.0.0.0:3306` inside the network
- First start: initializes database, creates user and schema
- Marker file `.inception_done` in the data directory prevents re-initialization
- If a pre-existing `mysql` directory has no marker, startup refuses to erase it. Inspect logs and credentials first. Restore a verified backup, or repair the interrupted initialization with a database administrator. Only create the marker after confirming the intended database, user and grants exist; never delete a populated database as an automatic retry.

### WordPress

- Image: `wordpress:inception`
- PHP-FPM listens on `9000` (configured in `conf/www.conf`)
- Installs WordPress via WP-CLI on first start
- Creates two users: admin + author
- The administrator login is `site_owner` by default; case-insensitive `admin` substrings and duplicate user logins are rejected
- File download, config creation and database installation are separate startup checks
- Redis Object Cache must connect before PHP-FPM starts

### NGINX

- Image: `nginx:inception`
- Generates a self-signed TLS certificate for `DOMAIN_NAME`
- TLS 1.2 and 1.3 only, port 443
- Proxies PHP to `wordpress:9000` via FastCGI
- Includes the domain in the certificate SAN; passes `HTTPS=on` to PHP-FPM
- Denies requests for dotfiles and `wp-config.php`

### Bonus services and backups

Redis runs internally with no published port. FTP uses the WordPress named volume, a dedicated user and passive ports 21100-21110. Static is HTML/CSS, not PHP. Adminer uses PHP's built-in HTTP server and connects to MariaDB over the bridge network. These exercise services are intended for an isolated VM, not public production hosting.

The backup daemon runs cron in the foreground. It takes an initial snapshot, then one daily at 02:00 UTC, retaining snapshots until they are more than seven full days old. Each snapshot has `database.sql.gz` and `wordpress.tar.gz`. A database dump uses `--single-transaction`; coordinate website writes for consistent database/files recovery. Check errors with `docker compose -f srcs/docker-compose.yml logs backup`.

Export a selected snapshot (replace the timestamp):

```bash
make backup
docker compose -f srcs/docker-compose.yml exec backup ls /backups
docker compose -f srcs/docker-compose.yml cp backup:/backups/snapshot-YYYYMMDDTHHMMSSZ ./snapshot
gzip -t snapshot/database.sql.gz
tar -tzf snapshot/wordpress.tar.gz
```

Restore into the existing, initialized stack, after privately backing up its current state. This overwrites the selected database and website files:

```bash
docker compose -f srcs/docker-compose.yml stop nginx wordpress ftp backup
gzip -dc snapshot/database.sql.gz | docker compose -f srcs/docker-compose.yml exec -T mariadb \
    bash -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot'
docker compose -f srcs/docker-compose.yml run --rm --no-deps -T --entrypoint tar wordpress \
    -xzf - -C /var/www/html < snapshot/wordpress.tar.gz
make
docker compose -f srcs/docker-compose.yml exec -T wordpress wp --allow-root cache flush
```

Flush Redis-backed object cache after restoration to discard values from the previous database state. Restored files must match the database snapshot; retain the corresponding local secrets. A SQL dump does not contain the MariaDB system-user passwords. Bootstrap a new database volume with the matching credentials first when recovering onto a fresh VM. Store exported snapshots outside Git.

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

- [ ] Run setup on the Debian VM; verify DockerRootDir and named volume mountpoints under `/home/<login>/data/`
- [ ] Update `/etc/hosts` on the evaluator's machine
- [ ] `make re` works on the VM without errors
- [ ] `https://ganersis.42.fr` loads WordPress
- [ ] `https://ganersis.42.fr/wp-admin/` accepts admin login
- [ ] Two WordPress users exist in the database
- [ ] No passwords in Git history
- [ ] `make check` passes; it uses temporary config, secrets, ports and volumes, leaving working data intact
- [ ] All eight services run; Redis is connected, FTP uploads/downloads and Adminer accesses MariaDB
- [ ] Static website is reachable; backup archives validate and restoration works on disposable data
- [ ] TLS 1.2/1.3 work and TLS 1.0/1.1 are rejected
- [ ] The mandatory daemons are PID 1 and restart after a process crash
- [ ] No host networking, links, latest tags, prebuilt service images or keepalive loops
- [ ] A peer reviewed the project and you can explain the Dockerfiles, secrets, PID 1 and volume design
