FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	mariadb-server \
	&& rm -rf /var/lib/apt/lists/* /var/lib/mysql/*

RUN mkdir -p /var/run/mysqld /var/lib/mysql \
	&& chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
