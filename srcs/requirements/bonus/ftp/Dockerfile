FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	vsftpd \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html /etc/vsftpd

COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 21 21100-21110

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
