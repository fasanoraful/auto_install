#!/bin/bash

set -e

echo "============================="
echo "Atualizando sistema"
echo "============================="
apt update && apt upgrade -y

echo "============================="
echo "Instalando dependências"
echo "============================="
apt install -y build-essential pkg-config \
libxml2-dev libsqlite3-dev libssl-dev \
libcurl4-openssl-dev libonig-dev libzip-dev \
libpng-dev libjpeg-dev libwebp-dev \
libfreetype6-dev libicu-dev libxslt1-dev \
libgettextpo-dev zlib1g-dev \
nginx mariadb-server wget curl unzip openssl

# ==============================
# PHP
# ==============================
echo "Escolha a versão do PHP:"
options=("8.3.7" "8.2.19" "8.1.28")
select opt in "${options[@]}"; do
    PHP_VERSION=$opt
    break
done

cd /usr/local/src
wget https://www.php.net/distributions/php-$PHP_VERSION.tar.gz
tar -xzf php-$PHP_VERSION.tar.gz
cd php-$PHP_VERSION

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
--enable-mysqlnd \
--with-mysqli \
--with-pdo-mysql \
--enable-opcache

make -j$(nproc)
make install

mkdir -p /usr/local/php/lib
cp php.ini-production /usr/local/php/lib/php.ini

# FIX MYSQL SOCKET
MYSQL_SOCKET=$(mysqladmin variables | grep socket | awk '{print $4}')

echo "mysqli.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini
echo "pdo_mysql.default_socket=$MYSQL_SOCKET" >> /usr/local/php/lib/php.ini

# ==============================
# PHP-FPM
# ==============================
mkdir -p /usr/local/php/etc/php-fpm.d
cp sapi/fpm/php-fpm.conf /usr/local/php/etc/php-fpm.conf

RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
MAX_CHILDREN=$((RAM_MB / 30))
[ "$MAX_CHILDREN" -lt 10 ] && MAX_CHILDREN=10
[ "$MAX_CHILDREN" -gt 200 ] && MAX_CHILDREN=200

cat > /usr/local/php/etc/php-fpm.d/www.conf <<EOF
[www]
user = www-data
group = www-data

listen = /run/php-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = $MAX_CHILDREN
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 20
EOF

mkdir -p /run
/usr/local/php/sbin/php-fpm

# ==============================
# SOCKET CHECK
# ==============================
for i in {1..10}; do
    [ -S "/run/php-fpm.sock" ] && break
    sleep 1
done

[ ! -S "/run/php-fpm.sock" ] && echo "Erro PHP-FPM" && exit 1

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

systemctl restart nginx

# CRIAR INDEX PADRÃO
echo "<?php echo 'Servidor OK'; ?>" > /var/www/html/index.php
chown -R www-data:www-data /var/www/html

# ==============================
# MARIADB
# ==============================
systemctl start mariadb

DB_ROOT_PASS=$(openssl rand -base64 16)
DB_USER="appuser"
DB_PASS=$(openssl rand -base64 16)

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -uroot -p$DB_ROOT_PASS -e "CREATE DATABASE appdb;"
mysql -uroot -p$DB_ROOT_PASS -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -uroot -p$DB_ROOT_PASS -e "GRANT ALL PRIVILEGES ON appdb.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# ==============================
# phpMyAdmin (CORRIGIDO)
# ==============================
cd /var/www/html
rm -rf phpmyadmin phpMyAdmin-*

wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
unzip phpMyAdmin-latest-all-languages.zip

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

# ==============================
# TESTE
# ==============================
sleep 2

curl -s http://localhost >/dev/null || (echo "NGINX FAIL" && exit 1)
curl -s http://localhost/phpmyadmin >/dev/null || (echo "PMA FAIL" && exit 1)

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

rm /var/www/html/phpMyAdmin-latest-all-languages.zip

echo "============================="
echo "TUDO FUNCIONANDO ✔"
echo "============================="