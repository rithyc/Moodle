#!/bin/bash

DEBIAN_FRONTEND=noninteractive apt-get -y update


printf "\n\n\n[`date +'%Y/%m/%d %H:%M:%S'`] Installing packages...\n\n\n"

# safer ones to avoid interrupting the live prod system esp during YPP...
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-client git graphviz aspell

sudo DEBIAN_FRONTEND=noninteractive apt-get -y install php7.4 php7.4-bcmath php7.4-bz2 php7.4-cli php7.4-common php7.4-curl php7.4-dev php7.4-fpm php7.4-gd php7.4-intl php7.4-json php7.4-mbstring php7.4-mysql php7.4-opcache php7.4-pgsql php7.4-readline php7.4-soap php7.4-xml php7.4-xmlrpc php7.4-zip php7.4-igbinary php7.4-redis php-pear
sleep 1s
sudo service php7.4-fpm stop

sudo apt-get -y install nginx
sleep 1s
sudo service nginx stop

# no longer use varnish

printf "\n\n\n[`date +'%Y/%m/%d %H:%M:%S'`] Copying configuration baseline...\n\n\n"

cd /
tar zxf /moodle/scripts/nodebaseline/srv_certs.tar.gz

cd /
rm -rf /mnt/localcache /mnt/.opcache
mkdir -p /mnt/localcache
mkdir -p /mnt/.opcache
chown -R 33:33 /mnt/localcache /mnt/.opcache

if [ -d "/var/www/html/moodle" ]; then
  mv /var/www/html/moodle /var/www/html/moodle_orig
fi
cd /
tar zxf /moodle/scripts/nodebaseline/var_www_html_moodle_azure_patched.tar.gz

cd /
rm -rf /etc/nginx /etc/php
tar zxf /moodle/scripts/nodebaseline/etc_nginx_php_ulimit_ssl_azure.tar.gz

cd /
tar zxf /moodle/scripts/nodebaseline/lib_systemd_system_services_azure.tar.gz
systemctl daemon-reload
sleep 3s

printf "\n\n\n[`date +'%Y/%m/%d %H:%M:%S'`] Starting services...\n\n\n"

sudo service php7.4-fpm start
sudo service nginx start

printf "\n\n\n[`date +'%Y/%m/%d %H:%M:%S'`] *** New Node Done...\n\n\n"
