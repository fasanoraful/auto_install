## Automatically install and setup LAMP on Ubuntu Server

This script can be used on blank ubuntu VPS/Dedivated server. This script can automatically install and setup the following :

```
1) Nginx Webserver 
2) Mariadb Database Server
3) PHP
4) PhpMyAdmin 
5) Let'sEncrypt SSL for website
```

## Installation Requirements :

```
1) Blank Ubuntu VPS/Dedicated server 
2) Root SSH access to server
3) Supported ubuntu versions:  16.04 LTS, 18.04 LTS, 20.04 LTS
```

## Installation Procedure :

#### 1. SSH to your server as root user:

#### 2. Download the script:
```
sudo wget https://raw.githubusercontent.com/fasanoraful/auto_install/main/lemp_install.sh
```

#### 3. Make the script executable
```
sudo chmod +x lemp_install.sh
```

#### 4. Execute the script:
```
sudo ./lemp_install.sh
```

