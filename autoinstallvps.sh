#!/bin/bash

set -e

LOG_FILE="/root/install-stack.log"
exec > >(tee -a "$LOG_FILE") 2>&1

TOTAL_STEPS=12
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    PERCENT=$((CURRENT_STEP * 100 / TOTAL_STEPS))

    FILLED=$((PERCENT / 2))
    EMPTY=$((50 - FILLED))

    BAR=$(printf "%${FILLED}s" | tr ' ' '#')
    SPACE=$(printf "%${EMPTY}s")

    printf "\r[%s%s] %d%%" "$BAR" "$SPACE" "$PERCENT"
}

clear

# ==============================
# Atualização
# ==============================
apt update -y >/dev/null 2>&1
apt upgrade -y >/dev/null 2>&1
progress

# ==============================
# Dependências
# ==============================
apt install -y build-essential pkg-config \
libxml2-dev libsqlite3-dev libssl-dev \
libcurl4-openssl-dev libonig-dev libzip-dev \
libpng-dev libjpeg-dev libwebp-dev \
libfreetype6-dev libicu-dev libxslt1-dev \
libgettextpo-dev zlib1g-dev \
libgmp-dev \
nginx mariadb-server wget curl unzip openssl >/dev/null 2>&1
progress

# ==============================
# PHP
# ==============================
echo
echo "Escolha a versão do PHP:"

options=("8.3.7" "8.2.19" "8.1.28")

select opt in "${options[@]}"; do
    PHP_VERSION=$opt
    break
done

cd /usr/local/src

wget -q https://www.php.net/distributions/php-$PHP_VERSION.tar.gz
tar -xzf php-$PHP_VERSION.tar.gz
cd php-$PHP_VERSION

progress

./configure --prefix=/usr/local/php \
--enable-fpm \
--with-fpm-user=www-data \
--with-fpm-group=www-data \
--with-openssl \
--with-zlib \
--with-curl \
--enable-mbstring \
--enable-bcmath \
--enable-intl \
--enable-soap \
--enable-zip \
--with-gettext \
--with-xsl \
--enable-exif \
--enable-gd \
--with-jpeg \
--with-webp \
--with-freetype \
--enable-gmp \
--enable-mysqlnd \
--with-mysqli \
--with-pdo-mysql \
--enable-opcache >/dev/null 2>&1

progress

# ==============================
# COMPILAÇÃO CONTROLADA
# ==============================
MAKE_THREADS=$(nproc)

[ "$MAKE_THREADS" -gt 4 ] && MAKE_THREADS=4

make -j$MAKE_THREADS >/dev/null 2>&1
make install >/dev/null 2>&1

progress

mkdir -p /usr/local/php/lib
cp php.ini-production /usr/local/php/lib/php.ini

# FIX MYSQL SOCKET
MYSQL_SOCKET=$(mysqladmin variables | grep socket | awk '{print $4}')

echo "mysqli.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini
echo "pdo_mysql.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini

# ==============================
# PHP-FPM OTIMIZADO
# ==============================
mkdir -p /usr/local/php/etc/php-fpm.d
cp sapi/fpm/php-fpm.conf /usr/local/php/etc/php-fpm.conf

RAM_MB=$(free -m | awk '/Mem:/ {print $2}')

MAX_CHILDREN=$((RAM_MB / 60))

[ "$MAX_CHILDREN" -lt 5 ] && MAX_CHILDREN=5
[ "$MAX_CHILDREN" -gt 80 ] && MAX_CHILDREN=80

cat > /usr/local/php/etc/php-fpm.d/www.conf <<EOF
[www]
user = www-data
group = www-data

listen = /run/php-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = $MAX_CHILDREN
pm.process_idle_timeout = 10s
pm.max_requests = 300
EOF

mkdir -p /run
/usr/local/php/sbin/php-fpm

progress

# ==============================
# SOCKET CHECK
# ==============================
for i in {1..10}; do
    [ -S "/run/php-fpm.sock" ] && break
    sleep 1
done

[ ! -S "/run/php-fpm.sock" ] && exit 1

chown www-data:www-data /run/php-fpm.sock

# ==============================
# NGINX
# ==============================
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name _;
    root /var/www/html;

    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

systemctl restart nginx >/dev/null 2>&1

echo "<?php echo 'Servidor OK'; ?>" > /var/www/html/index.php
chown -R www-data:www-data /var/www/html

progress

# ==============================
# MARIADB OTIMIZADO
# ==============================
systemctl start mariadb >/dev/null 2>&1

cat > /etc/mysql/mariadb.conf.d/99-performance.cnf <<EOF
[mysqld]

# RAM
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_method=O_DIRECT
innodb_flush_log_at_trx_commit=2

# CPU
max_connections=40
thread_cache_size=16
table_open_cache=256

# Temporários
tmp_table_size=32M
max_heap_table_size=32M

# Desabilitar query cache
query_cache_type=0
query_cache_size=0

# MyISAM
key_buffer_size=32M

# Performance
performance_schema=OFF
skip-name-resolve
EOF

systemctl restart mariadb >/dev/null 2>&1

DB_ROOT_PASS=$(openssl rand -base64 16)
DB_USER="appuser"
DB_PASS=$(openssl rand -base64 16)

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"

mysql -uroot -p$DB_ROOT_PASS -e "CREATE DATABASE appdb;"
mysql -uroot -p$DB_ROOT_PASS -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -uroot -p$DB_ROOT_PASS -e "GRANT ALL PRIVILEGES ON appdb.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

progress

# ==============================
# phpMyAdmin
# ==============================
cd /var/www/html

rm -rf phpmyadmin phpMyAdmin-*

wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip

unzip -qq phpMyAdmin-latest-all-languages.zip

PMA_DIR=$(find . -maxdepth 1 -type d -name "phpMyAdmin-*")

mv "$PMA_DIR" phpmyadmin

cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php

BLOWFISH=$(openssl rand -base64 32)

cat >> phpmyadmin/config.inc.php <<EOF
\$cfg['blowfish_secret'] = '$BLOWFISH';
\$cfg['Servers'][1]['host'] = '127.0.0.1';
\$cfg['Servers'][1]['connect_type'] = 'tcp';
EOF

chown -R www-data:www-data phpmyadmin

progress

# ==============================
# TESTE
# ==============================
sleep 2

curl -s http://localhost >/dev/null
curl -s http://localhost/phpmyadmin >/dev/null

progress

# ==============================
# CREDENCIAIS
# ==============================
cat > /root/credenciais.txt <<EOF
MYSQL ROOT: $DB_ROOT_PASS
DB: appdb
USER: $DB_USER
PASS: $DB_PASS
URL: http://SEU_IP/phpmyadmin
EOF

chmod 600 /root/credenciais.txt

rm -f /var/www/html/phpMyAdmin-latest-all-languages.zip

progress

echo
echo
echo "============================="
echo "INSTALAÇÃO CONCLUÍDA ✔"
echo "============================="
echo
echo "Credenciais:"
cat /root/credenciais.txt