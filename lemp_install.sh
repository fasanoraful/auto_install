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

# Receber parâmetros do usuário
read -p "Enter your admin email: " ADMIN_EMAIL
read -p "Enter PHP version (e.g., 7.4, 8.0): " PHP_VERSION
read -p "Enter your website name (e.g., example.com): " WEBSITE_NAME

# Configurações
INSTALL_NGINX="True"
INSTALL_PHP="True"
INSTALL_MYSQL="True"
CREATE_DATABASE="True"
DATABASE_NAME="db_name"
INSTALL_PHPMYADMIN="True"
ENABLE_SSL="False"

# Início da instalação
banner "Automatic LAMP Server Installation Started. Please wait! This might take several minutes to complete!"

# Restante do script...

# Atualização do servidor
echo -e "\n---- Updating Server ----"
apt install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
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

# Restante do script...

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

