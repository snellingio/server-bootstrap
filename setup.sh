#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade

# Add ppas
apt-get install -y software-properties-common
apt-add-repository ppa:nginx/development -y
apt-add-repository ppa:ondrej/php -y
apt-get update

# Install tools
apt-get install -y \
    build-essential net-tools curl fail2ban gcc git htop   \
    libmcrypt4 libpcre3-dev make supervisor ufw            \
    unattended-upgrades unzip wget whois zsh

# Restart ssh
ssh-keygen -A
service ssh restart

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Setup ufw
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Install base PHP packages
apt-get install -y \
    php7.1-cli php7.1-dev                           \
    php7.1-pgsql php7.1-sqlite3 php7.1-gd           \
    php7.1-curl php7.1-memcached                    \
    php7.1-imap php7.1-mysql php7.1-mbstring        \
    php7.1-xml php7.1-zip php7.1-bcmath php7.1-soap \
    php7.1-intl php7.1-readline php7.1-mcrypt

# Install Composer
curl -sS https://getcomposer.org/installer | php mv composer.phar /usr/local/bin/composer

# PHP cli configuration
sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.1/cli/php.ini
sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.1/cli/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.1/cli/php.ini
sudo sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.1/cli/php.ini

# Install nginx & php-fpm
apt-get install -y nginx php7.1-fpm

# Generate dhparam File
openssl dhparam -out /etc/nginx/dhparams.pem 2048

# Change php-fpm settings
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.1/fpm/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.1/fpm/php.ini
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.1/fpm/php.ini
sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.1/fpm/php.ini
sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.1/fpm/php.ini

# Change a few nginx settings
sed -i "s/worker_processes.*/worker_processes auto;/" /etc/nginx/nginx.conf
sed -i "s/# multi_accept.*/multi_accept on;/" /etc/nginx/nginx.conf
sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf

# Disable the default nginx site
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
service nginx restart

# Install a catch-all server
cat > /etc/nginx/sites-available/catch-all << EOF
server {
    return 404;
}
EOF

ln -s /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all

# Restart nginx & php-fpm
if [ ! -z "\$(ps aux | grep php-fpm | grep -v grep)" ]
then
    service php7.1-fpm restart
fi

service nginx restart
service nginx reload

# Configure supervisor autostart
systemctl enable supervisor.service
service supervisor start

# Configure swap
if [ -f /swapfile ]; then
    echo "Swap exists."
else
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo "vm.swappiness=30" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
fi

# Setup unattended security upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "Ubuntu xenial-security";
};
Unattended-Upgrade::Package-Blacklist {
    //
};
EOF

cat > /etc/apt/apt.conf.d/10periodic << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
