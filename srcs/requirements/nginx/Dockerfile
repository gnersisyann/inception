FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	nginx \
	openssl \
	gettext-base \
	curl \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl /etc/nginx/templates /var/www/html \
	&& rm -f /etc/nginx/sites-enabled/default

COPY conf/default.conf.template /etc/nginx/templates/default.conf.template
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
