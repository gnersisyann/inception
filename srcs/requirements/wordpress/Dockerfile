FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	php-fpm \
	php-mysql \
	php-redis \
	php-curl \
	php-gd \
	php-mbstring \
	php-xml \
	php-zip \
	curl \
	mariadb-client \
	redis-tools \
	libfcgi-bin \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar \
	&& chmod +x /usr/local/bin/wp

RUN mkdir -p /var/www/html /run/php \
	&& chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
