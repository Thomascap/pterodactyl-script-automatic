#!/bin/bash
#  -=-=-=-=-=-=-=-=-=-=-=- ( Pterodactyl Panel Script ) -=-=-=-=-=-=-=-=-=-=-=-  #
# This is a pterodactyl script for an installation of the latest panel version
# If you have a problem or found a bug in the script, you can contact us by mail or via discord
# This information can be found on our github page 
#
# Github: https://github.com/Thomascap/pterodactyl-script-automatic
##################################################################################
USE_DOMAIN=false
USE_SSL=false
MYSQL_PASSWORD=`head -c 8 /dev/random | base64`

dependency_install() {
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    apt-add-repository universe
    apt -y install php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
}

installing_composer() {
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

download_files() {
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
}

database_configuration() {
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"
}

installation() {
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
}

environment_configuration() {
    if [ "$USE_SSL" == true ]; then
        php artisan p:environment:setup --author=$EMAIL --url=https://$FQDN --timezone=Europe/Amsterdam --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379 --settings-ui=true
    elif [ "$USE_SSL" == false ]; then
        php artisan p:environment:setup --author=$EMAIL --url=http://$FQDN --timezone=Europe/Amsterdam --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379 --settings-ui=true
    fi
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password=$MYSQL_PASSWORD
}

database_setup() {
    php artisan migrate --seed --force
}

add_the_first_user() {
    php artisan p:user:make
}

set_permissions() {
    chown -R www-data:www-data /var/www/pterodactyl/*
}

crontab_configuration() {
    cronjob="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    (crontab -u root -l; echo "$cronjob" ) | crontab -u root -
}

create_queue_worker() {
    curl -o /etc/systemd/system/pteroq.service https://raw.githubusercontent.com/Thomascap/pterodactyl-script-automatic/pteroq.service
    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service
}

certbot() {
    sudo apt update
    sudo apt install -y certbot
    sudo apt install -y python3-certbot-nginx
    certbot certonly --nginx -d ${FQDN}
    cronjob="0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart nginx""
    (crontab -u root -l; echo "$cronjob" ) | crontab -u root -
}

webserver_configuration() {
    rm /etc/nginx/sites-enabled/default
    if [ "$USE_SSL" == true ]; then
        certbot_usage
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/Thomascap/pterodactyl-script-automatic/nginx_ssl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
    elif [ "$USE_SSL" == false ]; then
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/Thomascap/pterodactyl-script-automatic/nginx.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
    fi
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    sudo systemctl restart nginx
}