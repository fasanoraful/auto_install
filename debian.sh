#!/bin/bash
################################################################################
# Script for installing LEMP on Debian 10, 11, and 12
#-------------------------------------------------------------------------------
# Instala os seguintes componentes no seu servidor Debian:
# 1) Nginx Webserver 
# 2) MariaDB Database Server
# 3) PHP
# 4) PhpMyAdmin 
# 5) Let'sEncrypt SSL para o website
################################################################################

# Função de exibição de barra de progresso
function progress_bar() {
  local progress=$1
  local total=$2
  local percentage=$((progress * 100 / total))
  local bar_length=50
  local filled_length=$((bar_length * percentage / 100))
  local empty_length=$((bar_length - filled_length))
  local bar=""
  for ((i = 0; i < filled_length; i++)); do bar="${bar}#"; done
  for ((i = 0; i < empty_length; i++)); do bar="${bar}."; done
  echo -ne "\r[${bar}] ${percentage}%"
}

# Verificação se o script está sendo executado como root
if [ "$(whoami)" != 'root' ]; then
  echo "Por favor, execute este script como root!"
  echo "Use este comando para alternar para root:   sudo -i"
  exit 1
fi

# Recebendo parâmetros do usuário
read -p "Digite seu e-mail de administrador: " ADMIN_EMAIL
read -p "Digite a versão do PHP (ex: 7.4, 8.0, 8.1, 8.2): " PHP_VERSION
read -p "Digite o nome do seu site (ex: exemplo.com): " WEBSITE_NAME
read -p "Digite a senha para o banco de dados/phpMyAdmin: " MYSQL_PASSWORD_SET

# Configurações
INSTALL_NGINX="True"
INSTALL_PHP="True"
INSTALL_MYSQL="True"
CREATE_DATABASE="True"
DATABASE_NAME="db_name"
INSTALL_PHPMYADMIN="True"
ENABLE_SSL="False"

# Início da instalação
echo "Instalação automática do servidor LEMP iniciada."

# Atualização do sistema
echo -e "\n---- Atualizando o sistema ----"
apt update -y && apt upgrade -y
progress_bar 1 5

# Instalando pacotes essenciais
echo -e "\n---- Instalando pacotes básicos ----"
apt install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https unzip zip git htop
progress_bar 2 5

# Adicionando repositório do PHP para Debian
echo -e "\n---- Adicionando repositório do PHP ----"
wget -qO - https://packages.sury.org/php/apt.gpg | tee /etc/apt/trusted.gpg.d/php.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt update -y
progress_bar 3 5

# Instalando o Nginx
if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n---- Instalando Nginx ----"
  apt install nginx -y
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
    fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
  }

  location /phpmyadmin {
    root /usr/share;
    index index.php index.html index.htm;
    location ~ ^/phpmyadmin/(.+\.php)\$ {
      try_files \$uri =404;
      root /usr/share/;
      fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      include fastcgi_params;
    }
  }
}
EOF

  systemctl reload nginx
  echo "Nginx instalado e configurado."
  progress_bar 4 5
fi

# Instalação do PHP
if [ "$INSTALL_PHP" = "True" ]; then
  echo -e "\n---- Instalando PHP ----"
  apt install -y php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring php${PHP_VERSION}-gd php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-xml
  progress_bar 5 5
fi

# Finalização
echo -e "\n-----------------------------------------------------------"
echo "Instalação concluída com sucesso!"
if [ "$INSTALL_NGINX" = "True" ]; then
  echo "Website disponível em: http://$WEBSITE_NAME"
  echo "Diretório raiz: /var/www/html"
fi
if [ "$INSTALL_MYSQL" = "True" ]; then
  echo "Banco de dados criado: ${DATABASE_NAME}"
fi
if [ "$INSTALL_PHPMYADMIN" = "True" ]; then
  echo "Acesse PhpMyAdmin em: http://$WEBSITE_NAME/phpmyadmin"
fi
echo "-----------------------------------------------------------"

# Reiniciando o servidor
echo "O sistema será reiniciado em 10 segundos para aplicar as mudanças."
sleep 10
reboot
