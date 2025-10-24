#!/bin/bash
################################################################################
# Instalação manual LEMP (Linux, Nginx, MariaDB, PHP compilado) - Ubuntu 20+
#-------------------------------------------------------------------------------
# Autor: Victor Fasano (adaptado)
# Compatível com Ubuntu 20.04, 22.04, 24.04
# Funções:
# - Instala dependências
# - Compila PHP manualmente (versão informada)
# - Instala Nginx e MariaDB sob confirmação
################################################################################

# Função banner
function banner() {
  echo "+-----------------------------------------------------------------------+"
  printf "| %-65s |\n" "`date`"
  echo "|                                                                       |"
  printf "| %-65s |\n" "$1"
  echo "+-----------------------------------------------------------------------+"
}

# Verifica se é root
if [ "$(whoami)" != "root" ]; then
  echo "❌ Execute este script como root (use: sudo -i)"
  exit 1
fi

# Perguntas iniciais
read -p "Informe o domínio do site (ex: exemplo.com): " WEBSITE_NAME
read -p "Informe a versão do PHP para compilar (ex: 8.3.3): " PHP_VERSION
read -p "Deseja instalar o Nginx? (s/n): " INSTALL_NGINX
read -p "Deseja instalar o MariaDB? (s/n): " INSTALL_MYSQL
read -p "Deseja criar um banco de dados automaticamente? (s/n): " CREATE_DATABASE
if [[ "$CREATE_DATABASE" =~ ^[Ss]$ ]]; then
  read -p "Nome do banco de dados: " DATABASE_NAME
  read -p "Senha do usuário root do banco: " MYSQL_PASSWORD_SET
fi

banner "🚀 Iniciando Instalação Automática..."

# Atualiza sistema
echo -e "\n---- Atualizando sistema ----"
apt update -y && apt upgrade -y

# Instala dependências base
echo -e "\n---- Instalando dependências de compilação ----"
apt install -y build-essential pkg-config autoconf bison re2c libxml2-dev \
libsqlite3-dev libssl-dev libcurl4-openssl-dev libjpeg-dev libpng-dev \
libxpm-dev libwebp-dev libfreetype6-dev libzip-dev libonig-dev libicu-dev \
libreadline-dev libxslt1-dev libtidy-dev libgmp-dev libmysqlclient-dev unzip wget curl git

# Baixa e compila PHP manualmente
banner "🧱 Compilando PHP ${PHP_VERSION} manualmente..."

cd /usr/local/src
wget https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz || {
  echo "❌ Versão PHP inválida ou indisponível em php.net"
  exit 1
}
tar -xzf php-${PHP_VERSION}.tar.gz
cd php-${PHP_VERSION}

./configure --prefix=/usr/local/php-${PHP_VERSION} \
  --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
  --enable-mbstring --with-curl --with-openssl --with-zlib \
  --enable-bcmath --with-mysqli --with-pdo-mysql \
  --enable-intl --with-zip --with-gd --with-jpeg --with-webp --enable-opcache

make -j$(nproc)
make install

# Configuração PHP-FPM
cp sapi/fpm/php-fpm.conf /usr/local/php-${PHP_VERSION}/etc/php-fpm.conf
cp sapi/fpm/www.conf /usr/local/php-${PHP_VERSION}/etc/php-fpm.d/www.conf

# Adiciona php.ini básico
cat <<EOF > /usr/local/php-${PHP_VERSION}/lib/php.ini
[PHP]
date.timezone = America/Sao_Paulo
display_errors = On
memory_limit = 512M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 180
EOF

# Cria serviço systemd do PHP-FPM
cat <<EOF > /etc/systemd/system/php${PHP_VERSION}-fpm.service
[Unit]
Description=The PHP ${PHP_VERSION} FastCGI Process Manager
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/php-${PHP_VERSION}/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php-${PHP_VERSION}/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

# Instala Nginx se selecionado
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
    fastcgi_pass unix:/run/php-fpm-${PHP_VERSION}.sock;
  }

  location ~ /\.ht {
    deny all;
  }
}
EOF

  echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  systemctl enable nginx
  systemctl restart nginx
fi

# Instala MariaDB se selecionado
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

banner "✅ Instalação concluída!"
echo "PHP compilado manualmente em: /usr/local/php-${PHP_VERSION}"
echo "Verifique com: /usr/local/php-${PHP_VERSION}/bin/php -v"
echo "-----------------------------------------------------------"
if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
  echo "Site: http://$WEBSITE_NAME"
  echo "Document root: /var/www/html"
fi
echo "-----------------------------------------------------------"
echo "Sistema pronto para uso!"
