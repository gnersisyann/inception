FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	php-fpm \
	php-mysql \
	php-curl \
	php-gd \
	php-mbstring \
	php-xml \
	php-zip \
	curl \
	mariadb-client \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
	&& chmod +x /usr/local/bin/wp

RUN mkdir -p /var/www/html \
	&& chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
