#!/bin/bash
# ==========================================================
# setup_php_nginx_full.sh
# Instalação LEMP (opção apt ou compilar PHP) + detecção automática do socket
# Inclui modo --reset para limpar (remover) Nginx, PHP e configs.
# ==========================================================

set -o errexit
set -o pipefail
set -o nounset

# ---------- Helpers ----------
title(){ echo -e "\n\033[1;36m==> $1\033[0m\n"; }
err(){ echo -e "\033[1;31m[ERR]\033[0m $1"; }
info(){ echo -e "\033[1;33m[...]\033[0m $1"; }

if [ "$(whoami)" != "root" ]; then
  err "Execute com root: sudo -i"
  exit 1
fi

# ---------- Reset mode ----------
reset_all(){
  title "Reset total: removendo Nginx, PHP e artefatos"
  systemctl stop nginx 2>/dev/null || true
  systemctl stop php*-fpm 2>/dev/null || true
  apt-get remove --purge -y nginx nginx-common nginx-core php* php-fpm* mariadb-server mariadb-client || true
  apt-get autoremove -y
  apt-get autoclean -y

  rm -rf /etc/nginx /var/www/html /usr/local/php* /usr/src/php-* /run/php* /etc/systemd/system/php*-fpm* /etc/php /usr/local/bin/php-fpm || true
  systemctl daemon-reload || true

  echo "✅ Reset completo."
  exit 0
}

if [[ "${1:-}" == "--reset" ]]; then
  reset_all
fi

# ---------- Perguntas iniciais ----------
title "Instalação LEMP - escolha modo de instalação"

PS3="Escolha uma opção: "
options=("Instalar (APT) PHP x.y-fpm" "Compilar PHP manualmente" "Executar reset (--reset)" "Sair")
select opt in "${options[@]}"; do
  case $opt in
    "Instalar (APT) PHP x.y-fpm") MODE="apt"; break;;
    "Compilar PHP manualmente") MODE="compile"; break;;
    "Executar reset (--reset)") reset_all; break;;
    "Sair") exit 0;;
    *) echo "Opção inválida";;
  esac
done

read -rp "Domínio (server_name) a configurar (ex: victor.com) : " WEBSITE_NAME
read -rp "Instalar Nginx? (s/n) : " INSTALL_NGINX
read -rp "Instalar MariaDB? (s/n) : " INSTALL_MYSQL

# ---------- Atualiza e instala dependências gerais ----------
title "Atualizando sistema e instalando pacotes base"
apt-get update -y
apt-get upgrade -y
apt-get install -y wget curl build-essential unzip ca-certificates gnupg lsb-release software-properties-common

# ---------- Função para criar/atualizar config Nginx ----------
write_nginx_conf(){
  local socket="$1"
  local conf="/etc/nginx/sites-available/${WEBSITE_NAME}"
  cat > "$conf" <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${WEBSITE_NAME};
  root /var/www/html;
  index index.php index.html index.htm;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:${socket};
  }

  location ~ /\.ht { deny all; }
}
EOF

  ln -sf "$conf" /etc/nginx/sites-enabled/${WEBSITE_NAME}
  mkdir -p /var/www/html
  echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  chmod -R 755 /var/www/html
}

# ---------------- MODE APT ----------------
if [[ "$MODE" == "apt" ]]; then
  # Escolher versão apt disponível (oferecer 8.0/8.1/8.2/8.3 opções comuns)
  title "Instalação via APT: escolha a versão do PHP (se disponível nos repositórios)"
  apt_options=("8.0" "8.1" "8.2" "8.3" "Cancelar")
  select ver in "${apt_options[@]}"; do
    if [[ "$ver" == "Cancelar" ]]; then echo "Cancelado."; exit 0; fi
    if [[ "$ver" =~ ^[0-9]\.[0-9]$ ]]; then PHP_APT_VER="$ver"; break; else echo "Escolha inválida"; fi
  done

  # Adiciona PPA ondrej (opcional) para ter múltiplas versões - mas deixo como pergunta
  read -rp "Adicionar PPA ondrej/php para maior disponibilidade de versões? (s/n) : " ADD_PPA
  if [[ "$ADD_PPA" =~ ^[Ss]$ ]]; then
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
  fi

  info "Instalando php${PHP_APT_VER}-fpm e módulos básicos..."
  apt-get install -y "php${PHP_APT_VER}-fpm" "php${PHP_APT_VER}-cli" "php${PHP_APT_VER}-mysql" "php${PHP_APT_VER}-gd" "php${PHP_APT_VER}-mbstring" "php${PHP_APT_VER}-curl" "php${PHP_APT_VER}-zip" "php${PHP_APT_VER}-xml" || {
    err "Falha instalando pacotes php via apt. Verifique repositórios."
    exit 1
  }

  # socket padrão para apt-installed php is /run/php/phpX.Y-fpm.sock
  PHP_SOCKET="/run/php/php${PHP_APT_VER}-fpm.sock"
  PHP_SERVICE="php${PHP_APT_VER}-fpm.service"

  info "Ativando e iniciando serviço ${PHP_SERVICE}..."
  systemctl enable --now "${PHP_SERVICE}"

  # Instalar Nginx e configurar
  if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
    info "Instalando Nginx..."
    apt-get install -y nginx
    ufw allow 'Nginx HTTP' || true
    write_nginx_conf "$PHP_SOCKET"
    systemctl enable --now nginx
    systemctl restart nginx || true
  fi

  # instalar MariaDB se solicitado
  if [[ "$INSTALL_MYSQL" =~ ^[Ss]$ ]]; then
    info "Instalando MariaDB..."
    apt-get install -y mariadb-server
    systemctl enable --now mariadb
  fi

  # Verificações
  sleep 2
  title "Verificações rápidas"
  echo "PHP-FPM socket esperado: $PHP_SOCKET"
  ls -l "$PHP_SOCKET" 2>/dev/null || echo "❗ Socket não encontrado ainda, verifique 'systemctl status ${PHP_SERVICE}' e logs."
  systemctl status "$PHP_SERVICE" --no-pager | sed -n '1,5p' || true
  if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
    systemctl status nginx --no-pager | sed -n '1,5p' || true
    curl -s -I http://localhost | sed -n '1p' || true
  fi

  echo -e "\n✅ Instalação via APT concluída. Acesse http://${WEBSITE_NAME} (ou localhost)."
  exit 0
fi

# ---------------- MODE COMPILE ----------------
if [[ "$MODE" == "compile" ]]; then
  title "Compilar PHP manualmente"

  # Versões disponíveis para compilar
  versions=("8.0.30" "8.1.29" "8.2.23" "8.3.3" "Cancelar")
  PS3="Escolha versão para compilar: "
  select ver in "${versions[@]}"; do
    if [[ "$ver" == "Cancelar" ]]; then echo "Cancelado."; exit 0; fi
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then PHP_VERSION_FULL="$ver"; break; else echo "Inválido"; fi
  done

  # Dependências de build
  title "Instalando dependências de compilação"
  apt-get update -y
  apt-get install -y build-essential pkg-config autoconf bison re2c libxml2-dev \
    libsqlite3-dev libssl-dev libcurl4-openssl-dev libjpeg-dev libpng-dev \
    libwebp-dev libfreetype6-dev libzip-dev libonig-dev libicu-dev libreadline-dev \
    libxslt1-dev libgmp-dev libmysqlclient-dev wget tar

  cd /usr/src || exit 1
  if [ ! -f "php-${PHP_VERSION_FULL}.tar.gz" ]; then
    info "Baixando php-${PHP_VERSION_FULL}.tar.gz"
    wget -q "https://www.php.net/distributions/php-${PHP_VERSION_FULL}.tar.gz"
  fi
  tar -xzf "php-${PHP_VERSION_FULL}.tar.gz" -C /usr/src || true
  cd "php-${PHP_VERSION_FULL}" || { err "Fonte php não encontrada"; exit 1; }

  # Configure - exibir saída
  title "Executando ./configure (essa etapa pode demorar)"
  ./configure --prefix=/usr/local/php-"${PHP_VERSION_FULL}" \
    --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
    --with-zlib --with-curl --enable-mbstring --with-openssl \
    --with-pdo-mysql --with-zip --with-jpeg --with-png --enable-opcache \
    2>&1 | tee /tmp/php_configure.log

  title "make - compilando (mostrando saída)..."
  make -j"$(nproc)" 2>&1 | tee /tmp/php_make.log

  title "make install..."
  make install 2>&1 | tee /tmp/php_make_install.log

  # Configurar PHP-FPM confs
  title "Configurando PHP-FPM e systemd"
  mkdir -p /usr/local/php-"${PHP_VERSION_FULL}"/etc/php-fpm.d
  cp sapi/fpm/php-fpm.conf /usr/local/php-"${PHP_VERSION_FULL}"/etc/php-fpm.conf || true
  # Ajusta www.conf para socket por versão
  SOCKET_PATH="/run/php-fpm-${PHP_VERSION_FULL}.sock"
  cat > /usr/local/php-"${PHP_VERSION_FULL}"/etc/php-fpm.d/www.conf <<EOF
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

  # php.ini básico
  cp php.ini-development /usr/local/php-"${PHP_VERSION_FULL}"/lib/php.ini || true
  sed -i "s~;date.timezone =.*~date.timezone = America/Sao_Paulo~" /usr/local/php-"${PHP_VERSION_FULL}"/lib/php.ini || true

  # Links úteis
  ln -sf /usr/local/php-"${PHP_VERSION_FULL}"/sbin/php-fpm /usr/local/bin/php-fpm-"${PHP_VERSION_FULL}"
  ln -sf /usr/local/php-"${PHP_VERSION_FULL}"/bin/php /usr/local/bin/php-"${PHP_VERSION_FULL}"

  # systemd service
  SERVICE_NAME="php${PHP_VERSION_FULL}-custom.service"
  cat > /etc/systemd/system/"${SERVICE_NAME}" <<EOF
[Unit]
Description=PHP ${PHP_VERSION_FULL} FPM (custom)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/php-${PHP_VERSION_FULL}/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php-${PHP_VERSION_FULL}/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
Restart=always
PIDFile=/run/php-fpm-${PHP_VERSION_FULL}.pid

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"

  # Define PHP_SOCKET para uso posterior
  PHP_SOCKET="${SOCKET_PATH}"
  PHP_SERVICE="${SERVICE_NAME}"

  # Instalar Nginx se solicitado
  if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
    info "Instalando Nginx..."
    apt-get install -y nginx
    ufw allow 'Nginx HTTP' || true
    write_nginx_conf "${PHP_SOCKET}"
    systemctl enable --now nginx
    systemctl restart nginx || true
  fi

  # MariaDB
  if [[ "$INSTALL_MYSQL" =~ ^[Ss]$ ]]; then
    info "Instalando MariaDB..."
    apt-get install -y mariadb-server
    systemctl enable --now mariadb
  fi

  # Verificações
  sleep 2
  title "Verificações pós-compilação"
  echo "Socket do PHP-FPM esperado: ${PHP_SOCKET}"
  ls -l "${PHP_SOCKET}" 2>/dev/null || echo "❗ Socket não encontrado ainda. Verifique 'systemctl status ${SERVICE_NAME}' e os logs em journalctl -u ${SERVICE_NAME}"

  systemctl status "${SERVICE_NAME}" --no-pager | sed -n '1,6p' || true
  if [[ "$INSTALL_NGINX" =~ ^[Ss]$ ]]; then
    systemctl status nginx --no-pager | sed -n '1,6p' || true
    curl -s -I http://localhost | sed -n '1p' || true
  fi

  echo -e "\n✅ PHP compilado e serviços configurados. Acesse http://${WEBSITE_NAME}"
  exit 0
fi

# ------------- FIM -------------
