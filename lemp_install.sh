#!/bin/bash
################################################################################
# Script for installing LAMP on Ubuntu 16.04, 18.04 and 20.04 (could be used for other version too)
#-------------------------------------------------------------------------------
# This script can install the following automatically on your Ubuntu server.
# 1) Nginx Webserver 
# 2) Mariadb Database Server
# 3) PHP
# 4) PhpMyAdmin 
# 5) Let'sEncrypt SSL for website
################################################################################

# Set this to False if you don't need to install nginx webserver
INSTALL_NGINX="True"
# Set this to False if you don't need to install PHP
INSTALL_PHP="True"
# Set this to False if you don't need to install any database server  
INSTALL_MYSQL="True"
# SET this to True if you need to create a database 
CREATE_DATABASE="True" 
# Set the database name and user you want to create
DATABASE_NAME="db_name"
# Set this to True if you need to install PHPMYADMIN
INSTALL_PHPMYADMIN="True"
# Set your domain name to be mapped 
WEBSITE_NAME="sitename.com"
# Set this to True if you need to install Free SSL for the Website
ENABLE_SSL="False"
# Set admin email for issuing SSL
ADMIN_EMAIL="admin@example.com"


function generatePassword()
{
  echo "$(openssl rand -base64 12)"
}

if [ "$(whoami)" != 'root' ]; then
        echo "Please run this script as root user only! "
		echo "Use this command to switch to root user:   sudo -i "
        exit 1;
    fi

if [ $INSTALL_NGINX != "True" ] && [ $INSTALL_MYSQL != "True" ] && [ $INSTALL_PHP != "True" ]; then
        echo "Please set some values to True for the script to run! "
        exit 1;
    fi

banner()
{
  echo "+-----------------------------------------------------------------------+"
  printf "| %-40s |\n" "`date`"
  echo "|                                                                       |"
  printf "|`tput bold` %-40s `tput sgr0`|\n" "$@"
  echo "+-----------------------------------------------------------------------+"
}

banner "Automatic LAMP Server Installation Started.
Please wait !!  This might take several minutes to complete !! "

sleep 7;
#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Updating Server ----"
sudo apt-get update -y

#--------------------------------------------------
# Install Apache Webserver
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ]; then
echo -e "\n---- Installing Nginx Web Server ----"
sudo apt install nginx -y
sudo ufw allow 'Nginx HTTP'
cat <<EOF > ~/server.conf
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  client_max_body_size 0;

  root /var/www/html;

  index index.php index.html index.htm index.nginx-debian.html;

  server_name _;

  location / {
    try_files $uri $uri/ =404;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;

    location ~ ^/phpmyadmin {
  #error_log /var/log/nginx/error.log;
  #access_log /var/log/nginx/access.log;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
    }
  }

  location ~ ^/phpmyadmin/.*\.(jpg|jpeg|gif|css|png|js|ico|html)$ {
    root /usr/share;
  }

  location ~ /\.ht {
    deny all;
  }

  location /phpmyadmin {
    auth_basic "Admin Login";
    auth_basic_user_file /etc/nginx/pma_pass;
  #	allow IP_DA_SUA_MAQUINA_PARA_ACESSAR_A_DB;
  #	allow 127.0.0.1;
  #	deny  all;
  }

  location /otservlist_verification133566z {
  allow 37.187.146.122;
  allow 94.23.92.210;
  }
}

EOF

# REMOVER DEFAULT SERVER
unlink /etc/nginx/sites-available/default
sudo mv ~/server.conf /etc/nginx/sites-available/default
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
sudo nginx -t

echo "CONGRATULATIONS! Website is working. Remove this index.html page and put your website files" >> /var/www/html/index.html
sudo systemctl reload nginx
else
  echo "Nginx server isn't installed due to the choice of the user!"
fi


#--------------------------------------------------
# Install PHP
#--------------------------------------------------


if [ $INSTALL_PHP = "True" ]; then
echo -e "\n---- Installing PHP ----" 
sudo apt install php-fpm php-mysql -y
else
  echo "PHP isn't installed due to the choice of the user!"
fi


#--------------------------------------------------
# Install MariaDB Server
#--------------------------------------------------


if [ $INSTALL_MYSQL = "True" ]; then
echo -e "\n---- Installing MariaDB Server ----"
sudo apt-get install mariadb-server -y
else
  echo "MariaDB server isn't installed due to the choice of the user!"
fi


#--------------------------------------------------
# Install PhpMyAdmin
#--------------------------------------------------

if [ $INSTALL_PHPMYADMIN = "True" ] && [ $INSTALL_NGINX = "True" ] && [ $INSTALL_PHP = "True" ] && [ $INSTALL_MYSQL = "True"  ]; then
echo -e "\n---- Installing PhpMyAdmin ----"
sudo apt-get install phpmyadmin -y
sudo ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
sudo systemctl restart nginx
else
  echo "PhpMyAdmin isn't installed due to the choice of the user!"
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "admin@example.com" ];then
  sudo add-apt-repository ppa:certbot/certbot -y && sudo apt-get update -y
  sudo apt-get install certbot python3-certbot-nginx -y
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
fi

#--------------------------------------------------
# Create MySql database and User
#--------------------------------------------------

if [ $CREATE_DATABASE = "True" ] && [ $INSTALL_MYSQL = "True" ]; then
echo -e "\n---- Creating Database and User ----"


BIN_MYSQL=$(which mysql)
DATABASE_HOST='localhost'
DATABASE_PASS=$(generatePassword)
ROOTMYSQL_PASS=" "
SQL1="CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};"
SQL2="update user set plugin='' where User='root';"
SQL3="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DATABASE_PASS}';"
SQL4="FLUSH PRIVILEGES;"
$BIN_MYSQL -u root -e "${SQL1}${SQL2}${SQL3}${SQL4}"
cat <<EOF > ~/database.txt

   >> Host      : ${DATABASE_HOST}
   >> Port      : 3306
   >> Database  : ${DATABASE_NAME}
   >> User      : root
   >> Pass      : ${DATABASE_PASS}

EOF
echo "Successfully Created Database and User! "
else
  echo "Database isn't created due to the choice of the user!"
fi


echo "-----------------------------------------------------------"
echo "Done! Your setup is completed successfully. Specifications:"
if [ $INSTALL_NGINX = "True" ]; then
echo "Visit website: http://$WEBSITE_NAME "
echo "Document root:  /var/www/html"
echo "Nginx configuration file: /etc/nginx/sites-available/server "
echo "Check Nginx status:   systemctl status nginx"
fi
if [ $INSTALL_MYSQL = "True" ]; then
  echo "Check Mysql Status:  systemctl status mariadb"
fi
if [ $INSTALL_PHP = "True" ]; then
  echo "Check PHP version:  php -v"
fi
if [ $INSTALL_PHPMYADMIN = "True" ]; then
  echo "Access PhpMyAdmin: http://$WEBSITE_NAME/phpmyadmin"
fi
if [ $CREATE_DATABASE = "True" ]; then
    echo " Database details: "
    echo " >> Host      : ${DATABASE_HOST}"
	  echo " >> Port      : 3306 "
    echo " >> Database  : ${DATABASE_NAME}"
    echo " >> User      : root"
    echo " >> Pass      : ${DATABASE_PASS}"
  echo "Database information saved at : /root/database.txt"
fi
echo "-----------------------------------------------------------"


# Maquina da reebot auto
echo "Maquina sera reiniciada para efetivacao das alteracoes em 10 segundos."
sleep 15;
sudo reboot