# FreeScout (official "dist" branch) for Railway.
# Put this file and the docker/ folder in the ROOT of your fork (next to artisan).
FROM php:8.3-fpm-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      nginx supervisor gettext-base ca-certificates git unzip curl \
      libpng-dev libjpeg-dev libfreetype6-dev libzip-dev libicu-dev \
      libc-client-dev libkrb5-dev libssl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli gd zip intl imap opcache pcntl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY . /var/www/html

# Writable folders live on the Railway volume (/data); keep the shipped skeleton for first boot.
RUN mv storage /opt/storage.dist \
 && mkdir -p storage Modules public/modules bootstrap/cache public/css/builds public/js/builds \
 && cp docker/php.ini /usr/local/etc/php/conf.d/zz-freescout.ini \
 && cp docker/supervisord.conf /etc/supervisord.conf \
 && cp docker/nginx.conf.template /etc/nginx/nginx.conf.template \
 && cp docker/entrypoint.sh /usr/local/bin/entrypoint.sh \
 && chmod +x /usr/local/bin/entrypoint.sh \
 && rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
