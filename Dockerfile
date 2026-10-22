# syntax=docker/dockerfile:1
FROM php:8.4-fpm-bookworm

ENV TZ=Asia/Shanghai \
    PUID=1000 \
    PGID=1000 \
    DEBUG=false

# CI changes this value on every run so apt security updates are not cached.
ARG DEPENDENCY_REFRESH=local
RUN set -eux; \
    php -r 'exit(PHP_MAJOR_VERSION === 8 && PHP_MINOR_VERSION === 4 && version_compare(PHP_VERSION, "8.4.27", ">=") ? 0 : 1);'; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nginx supervisor curl ca-certificates tzdata passwd \
        libfreetype6 libjpeg62-turbo libpng16-16 libwebp7 libonig5 libzip4 libcurl4 \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libonig-dev libzip-dev libcurl4-openssl-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    for extension in gd mbstring zip bcmath curl ftp exif; do \
        if ! php -r "exit(extension_loaded('$extension') ? 0 : 1);"; then \
            docker-php-ext-install -j"$(nproc)" "$extension"; \
        fi; \
    done; \
    if ! php -r 'exit(extension_loaded("Zend OPcache") ? 0 : 1);'; then \
        docker-php-ext-install -j"$(nproc)" opcache; \
    fi; \
    docker-php-source delete; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    apt-get purge -y --auto-remove \
        $PHPIZE_DEPS libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libonig-dev libzip-dev libcurl4-openssl-dev; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

WORKDIR /app/web
COPY admin/ ./admin/
COPY api/ ./api/
COPY app/ ./app/
COPY config/ ./config/
COPY i/ ./i/
COPY install/ ./install/
COPY public/ ./public/
COPY index.php favicon.ico robots.txt LICENSE ./

COPY docker/container/nginx.conf /etc/nginx/nginx.conf
COPY docker/container/fastcgi.conf /etc/nginx/easyimage-fastcgi.conf
COPY docker/container/php.ini /usr/local/etc/php/conf.d/99-easyimage.ini
COPY docker/container/php-fpm.conf /usr/local/etc/php-fpm.d/zzzz-easyimage.conf
COPY docker/container/supervisord.conf /etc/supervisor/easyimage.conf
COPY docker/container/health.php docker/container/check-runtime.php /usr/local/share/easyimage/
COPY --chmod=755 docker/container/entrypoint.sh /usr/local/bin/easyimage-entrypoint
COPY --chmod=755 docker/container/healthcheck.sh /usr/local/bin/easyimage-healthcheck

RUN set -eux; \
    mkdir -p /opt/easyimage-defaults/config /opt/easyimage-defaults/i /app/web/admin/logs /logs /run/php; \
    cp -a config/. /opt/easyimage-defaults/config/; \
    cp -a i/. /opt/easyimage-defaults/i/; \
    chmod 755 app/upload.php; \
    find /app/web /usr/local/share/easyimage -type f -name '*.php' -print0 | xargs -0 -n1 php -l; \
    php /usr/local/share/easyimage/check-runtime.php

EXPOSE 80
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/usr/local/bin/easyimage-healthcheck"]
ENTRYPOINT ["/usr/local/bin/easyimage-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/easyimage.conf"]
