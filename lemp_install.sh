#!/bin/bash
################################################################################
# Script for installing LAMP on Ubuntu 16.04, 18.04, 20.04, and 22.04
#-------------------------------------------------------------------------------
# This script installs the following components on your Ubuntu server:
# 1) Nginx Webserver 
# 2) MariaDB Database Server
# 3) PHP
# 4) PhpMyAdmin 
# 5) Let'sEncrypt SSL for website
################################################################################

# Configurações
INSTALL_NGINX="True"
INSTALL_PHP="True"
INSTALL_MYSQL="True"
CREATE_DATABASE="True"
DATABASE_NAME="db_name"
INSTALL_PHPMYADMIN="True"
WEBSITE_NAME="sitename.com"
ENABLE_SSL="False"
ADMIN_EMAIL="admin@example.com"
PHP_VERSION="8.0" # Set your desired PHP version here

# Funções
function generatePassword() {
  openssl rand -base64 12
}

function banner() {
  echo "+-----------------------------------------------------------------------+"
  printf "| %-65s |\n" "`date`"
  echo "|                                                                       |"
  printf "| %-65s |\n" "$1"
  echo "+-----------------------------------------------------------------------+"
}

# Verificações iniciais
if [ "$(whoami)" != 'root' ]; then
  echo "Please run this script as root user only!"
  echo "Use this command to switch to root user:   sudo -i"
  exit 1
fi

if [ "$INSTALL_NGINX" != "True" ] && [ "$INSTALL_MYSQL" != "True" ] && [ "$INSTALL_PHP" != "True" ]; then
  echo "Please set some values to True for the script to run!"
  exit 1
fi

# Início da instalação
banner "Automatic LAMP Server Installation Started. Please wait! This might take several minutes to complete!"

# Atualização do servidor
echo -e "\n---- Updating Server ----"
apt install software-properties-common
add-apt-repository ppa:ondrej/php
apt-get update -y

# Instalação de bibliotecas adicionais
echo -e "\n---- Installing additional libraries ----"
apt-get install -y git unzip zip gdb screen htop build-essential pkg-config \
  libboost-dev libgmp3-dev libxml2-dev sqlite3 libsqlite3-dev \
  libtcmalloc-minimal4 liblua5.1-0 libmysqlclient-dev ccache \
  libboost-filesystem-dev libboost-regex-dev libboost-system-dev \
  libboost-thread-dev libboost-iostreams-dev

# Instalação do Nginx
if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n---- Installing Nginx Web Server ----"
  apt-get install nginx -y
  ufw allow 'Nginx HTTP'

  cat <<EOF > /etc/nginx/sites-available/default
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  client_max_body_size 0;

  root /var/www/html;
  index index.php index.html index.htm;

  server_name $WEBSITE_NAME;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
  }

  location ~ /\.ht {
    deny all;
  }

  location /phpmyadmin {
    root /usr/share;
    index index.php index.html index.htm;
    location ~ ^/phpmyadmin/(.+\.php)\$ {
      try_files \$uri =404;
      root /usr/share/;
      fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      include /etc/nginx/fastcgi_params;
    }
    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
      root /usr/share/;
    }
  }
}
EOF

  nginx -t && systemctl reload nginx
  echo "CONGRATULATIONS! Website is working. Remove this index.html page and put your website files" > /var/www/html/index.html
else
  echo "Nginx server isn't installed due to the choice of the user!"
fi

# Instalação do PHP
if [ "$INSTALL_PHP" = "True" ]; then
  echo -e "\n---- Installing PHP ----"
  apt-get install php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring php${PHP_VERSION}-gd php${PHP_VERSION}-curl php${PHP_VERSION}-zip -y
else
  echo "PHP isn't installed due to the choice of the user!"
fi

# Instalação do MariaDB
if [ "$INSTALL_MYSQL" = "True" ]; then
  echo -e "\n---- Installing MariaDB Server ----"
  apt-get install mariadb-server -y
else
  echo "MariaDB server isn't installed due to the choice of the user!"
fi

# Instalação do PhpMyAdmin
if [ "$INSTALL_PHPMYADMIN" = "True" ] && [ "$INSTALL_NGINX" = "True" ] && [ "$INSTALL_PHP" = "True" ] && [ "$INSTALL_MYSQL" = "True" ]; then
  echo -e "\n---- Installing PhpMyAdmin ----"
  echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | debconf-set-selections
  echo 'phpmyadmin phpmyadmin/app-password-confirm password root' | debconf-set-selections
  echo 'phpmyadmin phpmyadmin/mysql/admin-pass password root' | debconf-set-selections
  echo 'phpmyadmin phpmyadmin/mysql/app-pass password root' | debconf-set-selections
  echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect none' | debconf-set-selections
  apt-get install phpmyadmin -y
  mv /usr/share/phpmyadmin/ /usr/share/phpmyadmin_old/
  wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
  unzip phpMyAdmin-5.2.1-all-languages.zip
  mv phpMyAdmin-5.2.1-all-languages /usr/share/phpmyadmin
  ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
  systemctl restart nginx
else
  echo "PhpMyAdmin isn't installed due to the choice of the user!"
fi

# Habilitar SSL com Certbot
if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "admin@example.com" ]; then
  add-apt-repository ppa:certbot/certbot -y && apt-get update -y
  apt-get install certbot python3-certbot-nginx -y
  certbot --nginx -d "$WEBSITE_NAME" --noninteractive --agree-tos --email "$ADMIN_EMAIL" --redirect
  systemctl reload nginx
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
fi

# Criar banco de dados e usuário MySQL
if [ "$CREATE_DATABASE" = "True" ] && [ "$INSTALL_MYSQL" = "True" ]; then
  echo -e "\n---- Creating Database and User ----"
  DATABASE_PASS=$(generatePassword)
  mysql -u root <<MYSQL_SCRIPT
USE mysql;
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DATABASE_PASS}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  cat <<EOF > ~/database.txt
   >> Host      : localhost
   >> Port      : 3306
   >> Database  : ${DATABASE_NAME}
   >> User      : root
   >> Pass      : ${DATABASE_PASS}
EOF

  echo "Successfully Created Database and User! Details saved at ~/database.txt"
else
  echo "Database isn't created due to the choice of the user!"
fi

# Finalização
echo "-----------------------------------------------------------"
echo "Done! Your setup is completed successfully. Specifications:"
if [ "$INSTALL_NGINX" = "True" ]; then
  echo "Visit website: http://$WEBSITE_NAME"
  echo "Document root:  /var/www/html"
  echo "Nginx configuration file: /etc/nginx/sites-available/default"
  echo "Check Nginx status: systemctl status nginx"
fi
if [ "$INSTALL_MYSQL" = "True" ]; then
  echo "Check Mysql Status: systemctl status mariadb"
fi
if [ "$INSTALL_PHP" = "True" ]; then
  echo "Check PHP version: php -v"
fi
if [ "$INSTALL_PHPMYADMIN" = "True" ]; then
  echo "Access PhpMyAdmin: http://$WEBSITE_NAME/phpmyadmin"
fi
if [ "$CREATE_DATABASE" = "True" ]; then
  echo "Database information saved at: ~/database.txt"
fi
echo "-----------------------------------------------------------"

# Reiniciar a máquina
echo "Machine will be restarted to apply changes in 10 seconds."
sleep 10
reboot
