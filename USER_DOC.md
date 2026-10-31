# User Documentation

This guide explains how to use and manage the Inception stack as an end user or administrator.

## Services provided

| Service | What it does |
|---------|--------------|
| **NGINX** | Accepts HTTPS traffic on port 443 and forwards PHP requests to WordPress |
| **WordPress** | Runs the website and administration panel |
| **MariaDB** | Stores the WordPress database |
| **Redis** | Caches WordPress objects to reduce database reads |
| **FTP** | Uploads and downloads files in the WordPress website volume |
| **Static** | Serves the separate HTML/CSS website |
| **Adminer** | Provides a browser interface for MariaDB |
| **Backup** | Saves the database and website on startup and daily at 02:00 UTC |

The mandatory website is available at **https://<login>.42.fr**. Bonus services also expose their own ports. Examples below assume login `ganersis`; use the domain and usernames from your local `srcs/.env`.

## Start and stop the project

From the project root:

```bash
make        # Build and start all services
make stop   # Stop services, keep containers and data
make start  # Start existing stopped containers
make down   # Remove containers and network, keep data
make re     # Rebuild and recreate, keep data
make status # Show service state
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
| Administrator | `site_owner` | `secrets/credentials.txt` | Full admin |
| Second user | `ganersis_user` | `secrets/wp_user_password.txt` | Author |

> The administrator username intentionally does **not** contain `admin` or `administrator` (project requirement).

## Credentials

| Credential | File |
|------------|------|
| MariaDB root password | `secrets/db_root_password.txt` |
| MariaDB application user password | `secrets/db_password.txt` |
| WordPress admin password | `secrets/credentials.txt` |
| WordPress second-user password | `secrets/wp_user_password.txt` |
| FTP user password | `secrets/ftp_password.txt` |

**Never commit** `srcs/.env` or files inside `secrets/` to Git.

Setup preserves existing passwords. Read passwords privately on the VM; do not paste them into chats or logs. Changing a secret file alone does **not** change an already-created MariaDB or WordPress account. Change those passwords in the respective application/database, then update the matching secret file and recreate dependent containers. FTP re-reads its secret at startup. Keep the administrator password file in sync when changing the WordPress password through the dashboard.

## Bonus access

- Static website: `http://<VM_IP>:8080/` (or `STATIC_PORT` from `.env`).
- Adminer: `http://<VM_IP>:8081/`. Select MySQL, server `mariadb` (or `CONTAINER_MARIADB`), database `DB_NAME`, user `DB_USER`, password from `secrets/db_password.txt`.
- FTP: connect to `<VM_IP>:21` in passive mode, using `FTP_USER` and `secrets/ftp_password.txt`. Set `FTP_PASV_ADDRESS` to the reachable VM IPv4 address. Allow ports 21100-21110 through VM networking/firewalls. This is plain FTP for the isolated exercise VM, not encrypted production access.
- Backup: `make backup` creates a snapshot immediately. Snapshots are in the `backup_data` named volume; see DEV_DOC.md for export and restoration. Backups contain confidential database and configuration data.

Never expose Adminer or FTP to an untrusted network. The VM hosts entry does not configure DNS on your Mac or another computer; add the domain there as well.

## Check that services are running

```bash
make status
```

Expected output: eight services in `Up` state. MariaDB, Redis, WordPress and NGINX should report `healthy`; repeated restarts or `unhealthy` indicate a failure.

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
| Empty or broken site after changes | Inspect logs and restore a verified backup if needed; do not delete volumes |
| Port 443 already in use | Stop the conflicting service; retain port 443 for the mandatory stack |
| Docker permission denied | Log out/in after setup, or use `sudo make` |
| FTP cannot transfer files | Check the VM passive IPv4 address, ports 21100-21110 and FTP logs |
| MariaDB reports a missing marker | Existing data was preserved; follow the recovery guidance in DEV_DOC.md |
