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

### Project design choices

- **Base image:** Debian Bookworm (penultimate stable) for all services.
- **Custom Dockerfiles:** Every service is built from scratch; no pre-built application images from Docker Hub.
- **Configuration:** Non-sensitive values live in `srcs/.env`; passwords live in `secrets/` and are injected via Docker secrets.
- **Networking:** All containers communicate on a dedicated bridge network (`inception`). Only NGINX publishes a port.
- **Persistence:** Two named Docker volumes store the database and WordPress files.
- **Domain:** The site is served at `https://ganersis.42.fr` (mapped via `/etc/hosts` during evaluation).

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

This project uses a **bridge network** so MariaDB and WordPress stay internal while NGINX remains the only public entry point.

### Docker Volumes vs Bind Mounts

| Named volumes (macOS dev) | Bind mounts (Linux VM / evaluation) |
|----------------------------|-------------------------------------|
| Managed by Docker | Map directly to a host path |
| Simple local development | Required path: `/home/ganersis/data/` |
| Data survives `make down` | Data survives container rebuilds |
| Path is opaque on the host | Easy to inspect and back up on the VM |

On the evaluation VM, named volumes are replaced with bind mounts pointing to `/home/ganersis/data/mariadb` and `/home/ganersis/data/wordpress` (see `LINUX_VM` comments in `docker-compose.yml`).

## Instructions

### Prerequisites

- Docker and Docker Compose
- `make`
- Domain entry in `/etc/hosts`:
  ```
  127.0.0.1  ganersis.42.fr
  ```

### First-time setup (automated)

On a fresh Debian VM:

```bash
git clone <your-repo-url> inception
cd inception
./setup.sh
make
```

`setup.sh` installs Docker (Debian), creates `.env` and `secrets/`, configures Linux bind mounts, and adds `ganersis.42.fr` to `/etc/hosts`.

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
make down   # stop containers
make clean  # stop, remove volumes and local images
make re     # full reset + restart
```

Open: **https://ganersis.42.fr**

The browser will warn about the self-signed certificate — this is expected.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WordPress documentation](https://wordpress.org/documentation/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [WP-CLI documentation](https://wp-cli.org/)

### AI usage

AI (Cursor) was used during this project as a learning assistant:

| Task | How AI was used |
|------|-----------------|
| Understanding the subject | Explained architecture, requirements, and order of implementation |
| Project structure | Helped design the folder layout and `.gitignore` |
| Debugging | Identified issues (MariaDB bind address, php-fpm listen, volume init, duplicate email) |
| Documentation | Drafted README, USER_DOC, and DEV_DOC |
| Code | Dockerfile and entrypoint scripts were written collaboratively; all changes were reviewed and tested with `make` |

AI was **not** used as a blind copy-paste source. Every file was tested locally, and the reasoning behind each service was understood before submission.
