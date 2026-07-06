# User Documentation

This guide explains how to use and manage the Inception stack as an end user or administrator.

## Services provided

| Service | What it does |
|---------|--------------|
| **NGINX** | Accepts HTTPS traffic on port 443 and forwards PHP requests to WordPress |
| **WordPress** | Runs the website and administration panel |
| **MariaDB** | Stores the WordPress database |

From outside the infrastructure, only **https://ganersis.42.fr** is accessible.

## Start and stop the project

From the project root:

```bash
make        # Build and start all services
make down   # Stop all services
make re     # Full reset (removes data) and restart
```

To view live logs:

```bash
make logs
```

## Access the website

1. Make sure `/etc/hosts` contains:
   ```
   127.0.0.1  ganersis.42.fr
   ```
   On the evaluation VM, use the VM IP address instead of `127.0.0.1`.

2. Open in a browser:
   ```
   https://ganersis.42.fr
   ```

3. Accept the self-signed certificate warning (normal for this project).

## Access the administration panel

```
https://ganersis.42.fr/wp-admin/
```

### WordPress accounts

| Account | Username | Password location | Role |
|---------|----------|-------------------|------|
| Administrator | `ganersis` | `secrets/credentials.txt` | Full admin |
| Second user | `ganersis_user` | `secrets/wp_user_password.txt` | Author |

> The administrator username intentionally does **not** contain `admin` or `administrator` (project requirement).

## Credentials

| Credential | File |
|------------|------|
| MariaDB root password | `secrets/db_root_password.txt` |
| MariaDB application user password | `secrets/db_password.txt` |
| WordPress admin password | `secrets/credentials.txt` |
| WordPress second-user password | `secrets/wp_user_password.txt` |

**Never commit** `srcs/.env` or files inside `secrets/` to Git.

## Check that services are running

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected output: all three containers (`nginx`, `wordpress`, `mariadb`) in `Up` state.

Quick health checks:

```bash
# HTTPS responds
curl -sk --resolve ganersis.42.fr:443:127.0.0.1 https://ganersis.42.fr/ -o /dev/null -w "%{http_code}\n"
# Expected: 200

# Container logs (no repeating errors)
make logs
```

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Site not loading | Check `/etc/hosts`, then `make` |
| Certificate warning | Expected with self-signed TLS; proceed in browser |
| Empty or broken site after changes | `make re` for a clean restart (deletes data) |
| Port 443 already in use | Stop the conflicting service or change the host port in Compose |
