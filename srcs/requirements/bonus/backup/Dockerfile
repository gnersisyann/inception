FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
	cron mariadb-client ca-certificates gzip tar \
	&& rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tools/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]