#!/bin/bash
################################################################################
# Instalação manual LEMP (Linux, Nginx, MariaDB, PHP compilado) - Ubuntu 20+
#-------------------------------------------------------------------------------
# Autor: Victor Fasano (versão aprimorada: limpeza + detecção socket)
# Compatível com Ubuntu 20.04, 22.04, 24.04
################################################################################

function banner() {
  echo "+-----------------------------------------------------------------------+"
  printf "| %-65s |\n" "$(date)"
  echo "|                                                                       |"
  printf "| %-65s |\n" "$1"
  echo "+-----------------------------------------------------------------------+"
}

function show_progress() {
    local pid=$1
    local delay=1
    local spinstr='|/-\'
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

if [ "$(whoami)" != "root" ]; then
  echo "❌ Execute este script como root (use: sudo -i)"
  exit 1
fi

banner "⚠️  Limpando instalações antigas de LEMP/PHP/PhpMyAdmin..."

# ======== LIMPEZA DE INSTALAÇÕES ANTIGAS ========
systemctl stop nginx 2>/dev/null
systemctl stop mariadb 2>/dev/null
systemctl stop php*-fpm 2>/dev/null

systemctl disable nginx 2>/dev/null
systemctl disable mariadb 2>/dev/null
systemctl disable php*-fpm 2>/dev/null
rm -f /etc/systemd/system/php*-fpm.service
systemctl daemon-reload

apt purge -y nginx mariadb-server mariadb-client mariadb-common php*-fpm php-mbstring php-zip php-gd php-curl php-xml unzip wget
apt autoremove -y

rm -rf /usr/local/php-* /usr/share/phpmyadmin /var/www/html/phpmyadmin
rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

banner "✅ Limpeza concluída!"

# ======== SELEÇÃO DE VERSÃO DO PHP ==========
echo ""
echo "Selecione a versão do PHP para compilar:"
options=("8.0.30" "8.1.29" "8.2.23" "8.3.3" "Cancelar")
select opt in "${options[@]}"; do
  case $opt in
    "8.0.30"|"8.1.29"|"8.2.23"|"8.3.3")
      PHP_VERSION=$opt
      break
      ;;
    "Cancelar")
      echo "Instalação cancelada."
      exit 0
      ;;
    *) echo "Opção inválida, tente novamente."; continue;;
  esac
done

# ======== OUTRAS CONFIGURAÇÕES ==========
read -p "Informe o domínio do site (ex: exemplo.com): " WEBSITE_NAME
read -p "Deseja instalar o Nginx? (s/n): " INSTALL_NGINX
read -p "Deseja instalar o MariaDB? (s/n): " INSTALL_MYSQL
read -p "Deseja criar um banco de dados automaticamente? (s/n): " CREATE_DATABASE
read -p "Deseja instalar o PhpMyAdmin? (s/n): " INSTALL_PHPMYADMIN

if [[ "$CREATE_DATABASE" =~ ^[Ss]$ ]]; then
  read -p "Nome do banco de dados: " DATABASE_NAME
  read -p "Senha do usuário root do banco: " MYSQL_PASSWORD_SET
fi

banner "🚀 Iniciando Instalação Automática..."

# ======== ATUALIZA SISTEMA ==========
apt update -y && apt upgrade -y
apt install -y build-essential pkg-config autoconf bison re2c libxml2-dev \
libsqlite3-dev libssl-dev libcurl4-openssl-dev libjpeg-dev libpng-dev \
libwebp-dev libfreetype6-dev libzip-dev libonig-dev libicu-dev libreadline-dev \
libxslt1-dev libtidy-dev libgmp-dev libmysqlclient-dev unzip wget curl git

# ======== COMPILAÇÃO MANUAL DO PHP ==========
banner "🧱 Compilando PHP ${PHP_VERSION} manualmente..."
cd /usr/local/src || exit 1
wget -q https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz || {
  echo "❌ Erro: versão do PHP não encontrada em php.net"
  exit 1
}
tar -xzf php-${PHP_VERSION}.tar.gz
cd php-${PHP_VERSION} || exit 1

./configure --prefix=/usr/local/php-${PHP_VERSION} \
  --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
  --enable-mbstring --with-curl --with-openssl --with-zlib \
  --enable-bcmath --with-mysqli --with-pdo-mysql --enable-intl --with-zip \
  --with-gd --with-jpeg --with-webp --enable-opcache > /tmp/configure.log 2>&1 &
show_progress $!

make -j"$(nproc)" > /tmp/make.log 2>&1 &
show_progress $!

make install > /tmp/make_install.log 2>&1 &
show_progress $!

# ======== CONFIGURAÇÃO DO PHP-FPM ==========
mkdir -p /usr/local/php-${PHP_VERSION}/etc/php-fpm.d
cp sapi/fpm/php-fpm.conf /usr/local/php-${PHP_VERSION}/etc/php-fpm.conf

# Criar diretório de sockets
mkdir -p /run/php
SOCKET_PATH="/run/php/php-fpm-${PHP_VERSION}.sock"

cat <<EOF > /usr/local/php-${PHP_VERSION}/etc/php-fpm.d/www.conf
[www]
user = www-data
group = www-data
listen = ${SOCKET_PATH}
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

cat <<EOF > /usr/local/php-${PHP_VERSION}/lib/php.ini
[PHP]
date.timezone = America/Sao_Paulo
display_errors = On
memory_limit = 512M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 180
EOF

# ======== SYSTEMD PHP-FPM ==========
cat <<EOF > /etc/systemd/system/php${PHP_VERSION}-fpm.service
[Unit]
Description=PHP ${PHP_VERSION} FPM
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/php-${PHP_VERSION}/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php-${PHP_VERSION}/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
PIDFile=/run/php/php-fpm-${PHP_VERSION}.pid
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

# ======== AGUARDAR SOCKET ==========
echo "⏳ Aguardando PHP-FPM criar o socket..."
for i in {1..10}; do
    if [ -S "$SOCKET_PATH" ]; then
        echo "✅ Socket PHP detectado em: $SOCKET_PATH"
        break
    fi
    sleep 1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Não foi possível detectar o socket do PHP-FPM!"
    echo "Verifique se o serviço php${PHP_VERSION}-fpm está ativo com: systemctl status php${PHP_VERSION}-fpm"
    exit 1
fi

# ======== INSTALA NGINX SE ESCOLHIDO ==========
if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
  banner "🌐 Instalando Nginx..."
  apt install -y nginx
  ufw allow 'Nginx HTTP'

  cat <<EOF > /etc/nginx/sites-available/default
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  root /var/www/html;
  index index.php index.html index.htm;
  server_name $WEBSITE_NAME;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:${SOCKET_PATH};
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
      fastcgi_pass unix:${SOCKET_PATH};
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

  echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  systemctl enable nginx
  systemctl restart nginx
fi

# ======== INSTALA MARIADB SE ESCOLHIDO ==========
if [[ "$INSTALL_MYSQL" =~ ^[Ss]$ ]]; then
  banner "🗄️ Instalando MariaDB..."
  apt install -y mariadb-server
  systemctl enable mariadb
  systemctl start mariadb

  if [[ "$CREATE_DATABASE" =~ ^[Ss]$ ]]; then
    banner "📦 Criando banco de dados..."
    mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD_SET}';
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};
FLUSH PRIVILEGES;
MYSQL_SCRIPT
    cat <<EOF > ~/database.txt
Host: localhost
Database: ${DATABASE_NAME}
User: root
Password: ${MYSQL_PASSWORD_SET}
EOF
    echo "✅ Banco criado e senha configurada! Dados em ~/database.txt"
  fi
fi

# ======== INSTALA PHPMYADMIN SE ESCOLHIDO ==========
if [[ "$INSTALL_PHPMYADMIN" =~ ^[Ss]$ ]]; then
  banner "📦 Instalando PhpMyAdmin..."
  apt install -y php-mbstring php-zip php-gd php-curl php-xml unzip wget
  wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -O /tmp/phpmyadmin.zip
  unzip /tmp/phpmyadmin.zip -d /usr/share/
  mv /usr/share/phpMyAdmin-5.2.1-all-languages /usr/share/phpmyadmin
  ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
  systemctl restart nginx
fi

banner "✅ Instalação concluída!"
echo "PHP compilado manualmente em: /usr/local/php-${PHP_VERSION}"
echo "Socket detectado: ${SOCKET_PATH}"
echo "Verifique com: /usr/local/php-${PHP_VERSION}/bin/php -v"
if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
  echo "Site disponível em: http://$WEBSITE_NAME"
fi
if [[ "$INSTALL_PHPMYADMIN" =~ ^[Ss]$ ]]; then
  echo "PhpMyAdmin disponível em: http://$WEBSITE_NAME/phpmyadmin"
fi
