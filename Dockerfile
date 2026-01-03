FROM oraclelinux:9


# --------------------------------------------------
# Variables
# --------------------------------------------------
ENV ORACLE_HOME=/usr/lib/oracle/23/client64
ENV LD_LIBRARY_PATH=/usr/lib/oracle/23/client64/lib
ENV PATH=$PATH:/usr/lib/oracle/23/client64/bin
ENV APP_DIR=/var/www/laravel


# --------------------------------------------------
# Oracle Instant Client
# --------------------------------------------------
RUN dnf -y install oracle-instantclient-release-23ai-el9 && \
    dnf -y install \
        oracle-instantclient-basic \
        oracle-instantclient-devel \
        oracle-instantclient-sqlplus && \
    rm -rf /var/cache/dnf


# --------------------------------------------------
# PHP repos (Remi)
# --------------------------------------------------
RUN dnf -y install epel-release && \
    dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm && \
    dnf module reset php -y && \
    dnf module enable php:remi-8.4 -y


# --------------------------------------------------
# PHP + OCI8 (binario)
# --------------------------------------------------
RUN dnf -y install \
    php php-fpm php-cli \
    php-oci8 \
    php-mbstring php-xml php-curl php-zip php-bcmath \
    php-gd php-intl php-opcache \
    nginx git unzip composer \
    libaio libaio-devel curl && \
    dnf clean all


# --------------------------------------------------
# OPcache (producción)
# --------------------------------------------------
RUN cat << 'EOF' > /etc/php.d/10-opcache.ini
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.fast_shutdown=1
EOF


# --------------------------------------------------
# App
# --------------------------------------------------
RUN mkdir -p ${APP_DIR}
WORKDIR ${APP_DIR}
COPY . .


# --------------------------------------------------
# Permisos
# --------------------------------------------------
RUN chown -R nginx:nginx ${APP_DIR} && \
    chmod -R 775 storage bootstrap/cache

# --------------------------------------------------
# PHP-FPM runtime directory (FIX)
# --------------------------------------------------
RUN mkdir -p /run/php-fpm && \
    chown -R nginx:nginx /run/php-fpm

# --------------------------------------------------
# PHP-FPM config
# --------------------------------------------------
RUN sed -i \
  -e 's/user = apache/user = nginx/' \
  -e 's/group = apache/group = nginx/' \
  -e 's|listen = 127.0.0.1:9000|listen = /run/php-fpm/www.sock|' \
  -e 's/;listen.owner = nobody/listen.owner = nginx/' \
  -e 's/;listen.group = nobody/listen.group = nginx/' \
  -e 's/pm = dynamic/pm = ondemand/' \
  -e 's/pm.max_children = 50/pm.max_children = 20/' \
  -e 's/;pm.process_idle_timeout = 10s/pm.process_idle_timeout = 10s/' \
  -e 's/;pm.max_requests = 500/pm.max_requests = 500/' \
  /etc/php-fpm.d/www.conf


# --------------------------------------------------
# Nginx config
# --------------------------------------------------
RUN rm -f /etc/nginx/conf.d/default.conf && \
    cat << 'EOF' > /etc/nginx/conf.d/laravel.conf
server {
    listen 80;
    server_name _;
    server_tokens off;


    root /var/www/laravel/public;
    index index.php;


    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";


    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }


    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }


    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF


# --------------------------------------------------
# Healthcheck
# --------------------------------------------------
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost/ || exit 1


# --------------------------------------------------
# Expose + start
# --------------------------------------------------
EXPOSE 80
CMD ["sh", "-c", "php-fpm && nginx -g 'daemon off;'"]
