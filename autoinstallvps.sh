#!/bin/bash

set -e

LOG_FILE="/root/install-stack.log"
: > "$LOG_FILE"

progress_pid=""

start_progress() {
    local message="$1"
    local i=0
    local bar_size=30

    tput civis 2>/dev/null || true

    while true; do
        local pos=$((i % bar_size))
        local bar=""

        for ((j=0; j<bar_size; j++)); do
            if [ "$j" -le "$pos" ]; then
                bar+="#"
            else
                bar+="."
            fi
        done

        printf "\r%s [%s]" "$message" "$bar"
        sleep 0.1
        i=$((i + 1))
    done
}

stop_progress() {
    if [ -n "$progress_pid" ]; then
        kill "$progress_pid" >/dev/null 2>&1 || true
        wait "$progress_pid" 2>/dev/null || true
        progress_pid=""
    fi

    tput cnorm 2>/dev/null || true
    printf "\r%-100s\r"
}

run_step() {
    local message="$1"
    shift

    start_progress "$message" &
    progress_pid=$!

    "$@" >> "$LOG_FILE" 2>&1

    stop_progress
}

fail() {
    stop_progress
    echo
    echo "Erro durante a instalação."
    echo "Verifique o log em: $LOG_FILE"
    exit 1
}

trap fail ERR

# ==============================
# Atualizando sistema
# ==============================
run_step "Estamos instalando, aguarde..." apt update -y
run_step "Estamos instalando, aguarde..." apt upgrade -y

# ==============================
# Instalando dependências
# ==============================
run_step "Estamos instalando, aguarde..." apt install -y build-essential pkg-config \
libxml2-dev libsqlite3-dev libssl-dev \
libcurl4-openssl-dev libonig-dev libzip-dev \
libpng-dev libjpeg-dev libwebp-dev \
libfreetype6-dev libicu-dev libxslt1-dev \
libgettextpo-dev zlib1g-dev \
libgmp-dev \
nginx mariadb-server wget curl unzip openssl

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

run_step "Estamos instalando, aguarde..." wget https://www.php.net/distributions/php-$PHP_VERSION.tar.gz
run_step "Estamos instalando, aguarde..." tar -xzf php-$PHP_VERSION.tar.gz

cd php-$PHP_VERSION

run_step "Estamos instalando, aguarde..." ./configure --prefix=/usr/local/php \
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
--enable-opcache

MAKE_THREADS=$(nproc)
[ "$MAKE_THREADS" -gt 4 ] && MAKE_THREADS=4

run_step "Estamos instalando, aguarde..." make -j$MAKE_THREADS
run_step "Estamos instalando, aguarde..." make install

mkdir -p /usr/local/php/lib
cp php.ini-production /usr/local/php/lib/php.ini

MYSQL_SOCKET=$(mysqladmin variables | grep socket | awk '{print $4}')

echo "mysqli.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini
echo "pdo_mysql.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini

# ==============================
# PHP-FPM
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

run_step "Estamos instalando, aguarde..." /usr/local/php/sbin/php-fpm

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

    location /phpmyadmin {
        alias /usr/local/share/phpmyadmin;
        index index.php index.html;

        location ~ ^/phpmyadmin/(.+\.php)$ {
            alias /usr/local/share/phpmyadmin/\$1;
            include fastcgi_params;
            fastcgi_pass unix:/run/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME /usr/local/share/phpmyadmin/\$1;
        }
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

run_step "Estamos instalando, aguarde..." systemctl restart nginx

echo "<?php echo 'Servidor OK'; ?>" > /var/www/html/index.php
chown -R www-data:www-data /var/www/html

# ==============================
# MARIADB
# ==============================
run_step "Estamos instalando, aguarde..." systemctl start mariadb

cat > /etc/mysql/mariadb.conf.d/99-performance.cnf <<EOF
[mysqld]
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_method=O_DIRECT
innodb_flush_log_at_trx_commit=2

max_connections=40
thread_cache_size=16
table_open_cache=256

tmp_table_size=32M
max_heap_table_size=32M

query_cache_type=0
query_cache_size=0

key_buffer_size=32M

performance_schema=OFF
skip-name-resolve
EOF

run_step "Estamos instalando, aguarde..." systemctl restart mariadb

DB_ROOT_PASS=$(openssl rand -base64 16)
DB_USER="appuser"
DB_PASS=$(openssl rand -base64 16)

run_step "Estamos instalando, aguarde..." mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
run_step "Estamos instalando, aguarde..." mysql -uroot -p$DB_ROOT_PASS -e "CREATE DATABASE appdb;"
run_step "Estamos instalando, aguarde..." mysql -uroot -p$DB_ROOT_PASS -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
run_step "Estamos instalando, aguarde..." mysql -uroot -p$DB_ROOT_PASS -e "GRANT ALL PRIVILEGES ON appdb.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# ==============================
# phpMyAdmin FORA DO HTML
# ==============================
cd /tmp

rm -rf phpmyadmin phpMyAdmin-* phpMyAdmin-latest-all-languages.zip
rm -rf /usr/local/share/phpmyadmin

run_step "Estamos instalando, aguarde..." wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip

run_step "Estamos instalando, aguarde..." unzip phpMyAdmin-latest-all-languages.zip

PMA_DIR=$(find . -maxdepth 1 -type d -name "phpMyAdmin-*")

mv "$PMA_DIR" /usr/local/share/phpmyadmin

cp /usr/local/share/phpmyadmin/config.sample.inc.php /usr/local/share/phpmyadmin/config.inc.php

BLOWFISH=$(openssl rand -base64 32)

cat >> /usr/local/share/phpmyadmin/config.inc.php <<EOF
\$cfg['blowfish_secret'] = '$BLOWFISH';
\$cfg['Servers'][1]['host'] = '127.0.0.1';
\$cfg['Servers'][1]['connect_type'] = 'tcp';
EOF

chown -R www-data:www-data /usr/local/share/phpmyadmin

rm -f /tmp/phpMyAdmin-latest-all-languages.zip

# ==============================
# TESTE
# ==============================
sleep 2

run_step "Estamos instalando, aguarde..." curl -s http://localhost
run_step "Estamos instalando, aguarde..." curl -s http://localhost/phpmyadmin

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

stop_progress

echo
echo "============================="
echo "INSTALAÇÃO CONCLUÍDA ✔"
echo "============================="
echo
echo "Credenciais:"
cat /root/credenciais.txt
echo
echo "Log da instalação: $LOG_FILE"