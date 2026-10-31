*This project has been created as part of the 42 curriculum by ganersis.*

# Inception

## Description

Inception is a System Administration project that builds a small Docker-based infrastructure. The stack runs WordPress with PHP-FPM and MariaDB, exposed to the outside world only through an NGINX reverse proxy with TLS.

The goal is to practice containerization, service isolation, persistent storage, secrets management, and HTTPS configuration in a reproducible environment.

### Architecture

```
Browser (HTTPS :443)
        │
        ▼
     NGINX  ──fastcgi──▶  WordPress + PHP-FPM (:9000)
                                │
                                ▼
                            MariaDB (:3306)
```

| Service   | Role                                      |
|-----------|-------------------------------------------|
| `nginx`   | Single entry point, TLS 1.2/1.3, port 443 |
| `wordpress` | WordPress site + PHP-FPM (no NGINX inside) |
| `mariadb` | Database for WordPress                    |
| `redis` | WordPress object cache, internal port 6379 |
| `ftp` | File transfer to the WordPress named volume, ports 21 and 21100-21110 |
| `static` | HTML/CSS website, host port 8080 |
| `adminer` | Database administration, host port 8081 |
| `backup` | Database and website snapshots on startup and daily at 02:00 UTC |

### Project design choices

- **Base image:** Debian Bookworm (penultimate stable) for all services.
- **Custom Dockerfiles:** Every service is built from scratch; no pre-built application images from Docker Hub.
- **Configuration:** Non-sensitive values live in `srcs/.env`; passwords live in `secrets/` and are injected via Docker secrets.
- **Networking:** All containers communicate on a dedicated bridge network (`inception`). NGINX is the only entry point for the mandatory stack, on port 443; bonus FTP, static and Adminer publish additional ports as allowed by the subject.
- **Persistence:** Three Docker-managed named volumes store the database, WordPress files and backups. No bind mounts are used for these storages.
- **Domain:** The site is served at `https://<login>.42.fr`, mapped to the VM IP. Examples use `ganersis`; supply your actual 42 login to setup.
- **Startup:** Readiness checks gate MariaDB, Redis and PHP-FPM dependencies. Daemons run in the foreground as PID 1, with `restart: unless-stopped` for crash/reboot recovery unless explicitly stopped.

### VM vs Docker

| Virtual Machine | Docker |
|-----------------|--------|
| Full guest OS with its own kernel | Shares the host kernel; lighter isolation |
| Heavy resource usage (RAM, disk) | Lower overhead per service |
| Slow to boot and replicate | Fast to build, start, and tear down |
| Best for full OS-level tasks | Best for packaging and running applications |

In this project, Docker runs **inside** a VM. The VM provides the evaluation environment; Docker isolates each service.

### Secrets vs Environment Variables

| Environment variables (`.env`) | Secrets (`secrets/`) |
|-------------------------------|----------------------|
| Domain name, database names, usernames | Database passwords, WordPress admin password |
| Safe to structure as a template (`.env.example`) | Must never be committed to Git |
| Loaded via `env_file` in Compose | Mounted as files under `/run/secrets/` |
| Convenient for non-sensitive config | Better for credentials (read by entrypoint scripts) |

Passwords are **not** hard-coded in Dockerfiles. All credentials live in `secrets/` and are injected via Docker secrets at runtime.

### Docker Network vs Host Network

| Bridge network (`inception`) | Host network |
|------------------------------|--------------|
| Containers talk by service name (`mariadb`, `wordpress`) | Container shares the host network stack |
| Only NGINX exposes port 443 | All services could expose ports directly |
| Isolated and predictable | Breaks service separation (forbidden in this project) |

This project uses a **bridge network** so MariaDB, PHP-FPM and Redis stay internal. Bonus ports are separate from the mandatory HTTPS entry point.

### Docker Volumes vs Bind Mounts

| Named volumes (used here) | Bind mounts (not used for persistent storage) |
|--------------------------|----------------------------------------------|
| Docker creates and manages storage | Map an existing host directory directly |
| Referenced by volume name in Compose | Referenced by a host filesystem path |
| Inspected with `docker volume inspect` | Managed with host filesystem tools |
| Survive container deletion | Survive container deletion |

On the VM, setup configures Docker's `data-root` as `/home/<login>/data/docker`. Named volume contents therefore live under `/home/<login>/data/docker/volumes/<volume-name>/_data`. This changes the storage root for the **entire Docker daemon**, not just this project. Setup refuses to change it when existing Docker containers, images or volumes are present; it never migrates or deletes their data. Other daemon settings are preserved. See DEV_DOC.md for inspection and recovery.

## Instructions

### Prerequisites

- A fresh Debian 13 Linux VM, with a non-root user and root access through `sudo` or `su`
- Docker Engine and Compose v2.24.4 or newer (`setup.sh` installs the official packages)
- `make`, Bash, Git, curl, OpenSSL and jq
- Domain entry in `/etc/hosts`:
  ```
  127.0.0.1  ganersis.42.fr
  ```

### First-time setup (automated)

On a fresh Debian VM:

```bash
git clone <your-repo-url> inception
cd inception
bash setup.sh ganersis
# If setup added your account to the docker group, log out and back in first.
make
```

Replace `ganersis` with your 42 login. Setup installs Docker, creates `.env` and missing secrets, configures Docker-managed volume storage and adds the domain to the VM's `/etc/hosts`. To browse from macOS, also add `<VM_IP> <login>.42.fr` to macOS `/etc/hosts`. Use bridged networking or configure VM port forwarding. Never change the mandatory host port 443 for evaluation.

If `git` or `sudo` is missing on a fresh Debian installation, enter a root shell with `su -`, install `git sudo`, add your account to the `sudo` group, then log in again before cloning. Allocate enough disk for all images and snapshots (20 GB or more is a practical starting point).

### First-time setup (manual)

```bash
cp srcs/.env.example srcs/.env
# Fill in srcs/.env with your values

# Create secrets/ files (one password per file, single line, no quotes):
#   secrets/db_root_password.txt
#   secrets/db_password.txt
#   secrets/credentials.txt
#   secrets/wp_user_password.txt
#   secrets/ftp_password.txt
```

### Run the project

```bash
make        # build images + start containers
make logs   # follow logs
make down   # remove containers/network, keep persistent data
make clean  # also remove locally built images, keep volumes
make re     # rebuild and recreate, keep data
make status # show service status
make backup # create a snapshot immediately
make check  # isolated integration test, cleans up its own test volumes
```

Open: **https://ganersis.42.fr**

The browser will warn about the self-signed certificate — this is expected.

User access, credentials and troubleshooting: [USER_DOC.md](USER_DOC.md). Developer setup, volume inspection, backups and evaluation checks: [DEV_DOC.md](DEV_DOC.md).

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WordPress documentation](https://wordpress.org/documentation/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [WP-CLI documentation](https://wp-cli.org/)
- [Docker daemon data directory](https://docs.docker.com/engine/daemon/#daemon-data-directory)
- [Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Redis Object Cache](https://wordpress.org/plugins/redis-cache/)
- [Adminer](https://www.adminer.org/)
- [MariaDB dump documentation](https://mariadb.com/kb/en/mariadb-dump/)

### AI usage

AI (Cursor and GitHub Copilot) assisted with the following tasks:

| Task | How AI was used |
|------|-----------------|
| Understanding the subject | Explained architecture, requirements, and order of implementation |
| Project structure | Helped design the folder layout and `.gitignore` |
| Debugging | Identified issues (MariaDB bind address, php-fpm listen, volume init, duplicate email) |
| Documentation | Drafted README, USER_DOC, and DEV_DOC |
| Code | Assisted with Dockerfiles, startup scripts, named-volume setup, readiness checks, FTP fixes and the backup service |
| Validation | Helped implement `make check` for container startup, WordPress users, Redis, TLS, FTP, backups and persistence |

Container integration checks run locally with Docker Desktop. This does not prove that the Debian VM bootstrap, external network access or evaluation requirements have passed. Run the VM checklist, understand each script and seek peer review before submission.
