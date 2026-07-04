FROM debian:bookworm

RUN apt-get update && apt-get install -y \
	nginx \
	&& rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/nginx/sites-enabled/default

COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY site /var/www/static

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
