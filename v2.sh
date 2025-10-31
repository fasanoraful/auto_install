#!/bin/bash
################################################################################
# Script for installing LAMP on Ubuntu 16.04, 18.04, 20.04, and 22.04
#-------------------------------------------------------------------------------
# Updated to compile PHP manually from source (no Ondrej repository)
# Includes automatic MySQL socket configuration for PHP and phpMyAdmin
################################################################################

function banner() {
  echo "+-----------------------------------------------------------------------+"
  printf "| %-65s |\n" "`date`"
  echo "|                                                                       |"
  printf "| %-65s |\n" "$1"
  echo "+-----------------------------------------------------------------------+"
}

# Verificação de root
if [ "$(whoami)" != 'root' ]; then
  echo "Please run this script as root user only!"
  echo "Use this command to switch to root user:   sudo -i"
  exit 1
fi

# Parâmetros
read -p "Enter your admin email: " ADMIN_EMAIL
read -p "Enter PHP version (e.g., 8.0.30, 8.1.30, 8.2.25, 8.3.12): " PHP_VERSION
read -p "Enter your website name (e.g., example.com): " WEBSITE_NAME
read -p "Enter your database/phpmyadmin password: " MYSQL_PASSWORD_SET

INSTALL_NGINX="True"
INSTALL_PHP="True"
INSTALL_MYSQL="True"
CREATE_DATABASE="True"
DATABASE_NAME="db_name"
INSTALL_PHPMYADMIN="True"
ENABLE_SSL="False"

banner "Automatic LAMP Server Installation Started. Please wait! This might take several minutes to complete!"

# Atualização e dependências
echo -e "\n---- Updating Server ----"
apt-get update -y
apt-get install -y build-essential curl git wget unzip tar pkg-config libxml2-dev libsqlite3-dev libssl-dev libcurl4-openssl-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libonig-dev libzip-dev libreadline-dev libxslt1-dev libicu-dev zlib1g-dev mariadb-client apache2-utils

# ========================
# INSTALAÇÃO DO NGINX
# ========================
if [ "$INSTALL_NGINX" = "True" ]; then
 echo -e "\n---- Installing Nginx Web Server ----"
apt-get install nginx -y
ufw allow 'Nginx HTTP'

cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.php index.html index.htm;

    client_max_body_size 100M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Bloqueia .htaccess / .htpasswd
    location ~ /\.ht {
        deny all;
    }

    # phpMyAdmin
    location /phpmyadmin {
        alias /usr/share/phpmyadmin;

        auth_basic "Área restrita";
        auth_basic_user_file /etc/phpmyadmin/.htpasswd;

        index index.php index.html index.htm;

        location ~ ^/phpmyadmin/(.+\.php)\$ {
            try_files \$uri =404;
            fastcgi_pass unix:/run/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            include fastcgi_params;
        }

        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
            alias /usr/share/phpmyadmin/;
        }
    }

    # Otservlist Verification
    location /otservlist_verification133566z {
        allow 178.33.50.155;
        allow 94.23.92.210;
        deny all;
    }
}
EOF
  nginx -t && systemctl reload nginx
  echo "CONGRATULATIONS! Website is working. Remove this index.html page and put your website files" > /var/www/html/index.html
fi

# ========================
# COMPILAÇÃO MANUAL DO PHP
# ========================
if [ "$INSTALL_PHP" = "True" ]; then
  echo -e "\n---- Compiling PHP from Source ($PHP_VERSION) ----"

  SRC_DIR="/usr/local/src/php"
  INSTALL_DIR="/usr/local/php/$PHP_VERSION"
  FPM_SERVICE="/etc/systemd/system/php-fpm-${PHP_VERSION}.service"
  FPM_SOCKET="/run/php-fpm.sock"
  MYSQL_SOCKET="/run/mysqld/mysqld.sock"

  mkdir -p $SRC_DIR && cd $SRC_DIR

  wget -q https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz -O php.tar.gz
  tar -xzf php.tar.gz && cd php-${PHP_VERSION}

  ./configure --prefix=$INSTALL_DIR \
    --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
    --enable-mbstring --with-curl --with-openssl --with-zlib \
    --enable-bcmath --enable-intl --enable-zip --enable-soap \
    --with-mysqli --with-pdo-mysql --with-xsl \
    --with-jpeg --with-webp --with-freetype \
    --with-gettext --enable-gd --enable-exif --enable-opcache

  make -j$(nproc)
  make install

  # Configurações básicas
  mkdir -p $INSTALL_DIR/etc
  cp php.ini-production $INSTALL_DIR/etc/php.ini

  # Configurar socket do MySQL no php.ini
  echo -e "\n; Configuração automática do MySQL socket" >> $INSTALL_DIR/etc/php.ini
  echo "mysqli.default_socket = $MYSQL_SOCKET" >> $INSTALL_DIR/etc/php.ini
  echo "pdo_mysql.default_socket = $MYSQL_SOCKET" >> $INSTALL_DIR/etc/php.ini
  echo "mysql.default_socket = $MYSQL_SOCKET" >> $INSTALL_DIR/etc/php.ini

  # Configuração PHP-FPM
  mkdir -p /etc/php-fpm.d
  cat > /etc/php-fpm.d/www.conf <<EOF
[www]
user = www-data
group = www-data
listen = $FPM_SOCKET
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 100
pm.start_servers = 10
pm.min_spare_servers = 10
pm.max_spare_servers = 30
EOF

  # Serviço systemd PHP-FPM
  cat > $FPM_SERVICE <<EOF
[Unit]
Description=PHP-FPM ${PHP_VERSION}
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/sbin/php-fpm --nodaemonize --fpm-config /etc/php-fpm.d/www.conf
PIDFile=/run/php-fpm.pid
Restart=always
Environment=MYSQL_UNIX_PORT=$MYSQL_SOCKET

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /run
  systemctl daemon-reload
  systemctl enable php-fpm-${PHP_VERSION}
  systemctl start php-fpm-${PHP_VERSION}

  echo "✅ PHP $PHP_VERSION compiled and installed at $INSTALL_DIR"
  echo "✅ PHP-FPM socket created at $FPM_SOCKET"
  echo "✅ MySQL socket configured at $MYSQL_SOCKET"
else
  echo "PHP isn't installed due to user choice!"
fi

# ========================
# INSTALAÇÃO DO MARIADB
# ========================
if [ "$INSTALL_MYSQL" = "True" ]; then
  echo -e "\n---- Installing MariaDB Server ----"
  apt-get install mariadb-server -y
fi

# ========================
# INSTALAÇÃO DO PHPMYADMIN
# ========================
if [ "$INSTALL_PHPMYADMIN" = "True" ]; then
  echo -e "\n---- Installing PhpMyAdmin ----"
  wget https://files.phpmyadmin.net/phpMyAdmin/5.2.3/phpMyAdmin-5.2.3-all-languages.zip
  unzip -qq phpMyAdmin-5.2.3-all-languages.zip
  mv phpMyAdmin-5.2.3-all-languages /usr/share/phpmyadmin
  ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
  rm -rf phpMyAdmin-5.2.3-all-languages.zip

  # Configuração automática do socket no config.inc.php
  CONFIG_FILE="/usr/share/phpmyadmin/config.inc.php"
  mkdir -p $(dirname $CONFIG_FILE)
  cat > $CONFIG_FILE <<'EOF'
<?php
$i = 1;
$cfg['blowfish_secret'] = 'ChangeThisToARandomSecretString123!';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['connect_type'] = 'socket';
$cfg['Servers'][$i]['extension'] = 'mysqli';

$possibleSockets = [
    '/run/mysqld/mysqld.sock',
    '/var/run/mysqld/mysqld.sock',
    '/tmp/mysql.sock'
];

foreach ($possibleSockets as $sock) {
    if (file_exists($sock)) {
        $cfg['Servers'][$i]['socket'] = $sock;
        break;
    }
}
?>
EOF

  systemctl restart nginx
fi

# ========================
# CRIAÇÃO DO BANCO DE DADOS
# ========================
if [ "$CREATE_DATABASE" = "True" ]; then
  echo -e "\n---- Creating Database ----"
  mysql -u root <<MYSQL_SCRIPT
USE mysql;
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD_SET}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
  echo "Database ${DATABASE_NAME} created!"
fi

# ========================
# FINAL
# ========================

sudo mkdir -p /etc/phpmyadmin && sudo bash -c 'echo "root:$(openssl passwd -apr1 ${MYSQL_PASSWORD_SET})" > /etc/phpmyadmin/.htpasswd'

echo "-----------------------------------------------------------"
echo "✅ Setup complete!"
echo "Website: http://$WEBSITE_NAME"
echo "PHP version: $PHP_VERSION"
echo "PhpMyAdmin: http://$WEBSITE_NAME/phpmyadmin"
echo "-----------------------------------------------------------"
