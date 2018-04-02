#!/bin/bash

#
# BSD 3-Clause License
# 
# Copyright (c) 2018, Alban Vidal <alban.vidal@zordhak.fr>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

################################################################################
##########                    Define color to output:                 ########## 
################################################################################
_WHITE_="tput sgr0"
_RED_="tput setaf 1"
_GREEN_="tput setaf 2"
_ORANGE_="tput setaf 3"
################################################################################

# TODO
# - logrotate (all CT)
# - iptables isolateur: Deny !80 !443

# Load Vars
. 00_VARS

# Load Network Vars
. 01_NETWORK_VARS

################################################################################

#### CLOUD

# Test if Nextcloud database password is set
if [ ! -f /tmp/lxc_nextcloud_password ] ; then
    echo "$($_RED_)You need to create « /tmp/lxc_nextcloud_password » with nextcloud user passord$($_WHITE_)"
    exit 1
fi
MDP_nextcoud="$(cat /tmp/lxc_nextcloud_password)"

echo "$($_GREEN_)BEGIN cloud$($_WHITE_)"

echo "$($_ORANGE_)Create and attach /srv/data-cloud directory$($_WHITE_)"
mkdir -p /srv/data-cloud
chown 1000033:1000033 /srv/data-cloud
lxc config device add cloud sharedCloud disk path=/srv/data-cloud source=/srv/data-cloud

echo "$($_ORANGE_)Update, upgrade and packages$($_WHITE_)"
lxc exec cloud -- apt-get update > /dev/null
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null"
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim apt-utils > /dev/null"
 
echo "$($_ORANGE_)Create « occ » alias command$($_WHITE_)"
lxc exec cloud -- bash -c 'echo "sudo -u www-data php /var/www/nextcloud/occ \$@" > /usr/local/bin/occ
                           chmod +x /usr/local/bin/occ
                           '

echo "$($_ORANGE_)Install packages for nextcloud...$($_WHITE_)"
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install \
    wget            \
    curl            \
    sudo            \
    apache2         \
    mariadb-client  \
    redis-server    \
    php7.0 php7.0-fpm php7.0-simplexml php-mysql php-gd php-zip php-mbstring php-curl php-redis php7.0-bz2 php7.0-intl php7.0-mcrypt php7.0-gmp \
    > /dev/null"

echo "$($_ORANGE_)apache2 FIX ServerName$($_WHITE_)"
lxc exec cloud -- bash -c "echo 'ServerName $FQDN' > /etc/apache2/conf-available/99_ServerName.conf
                           a2enconf 99_ServerName > /dev/null"

echo "$($_ORANGE_)Enable php7-fpm in apache2$($_WHITE_)"
lxc exec cloud -- bash -c "a2enmod proxy_fcgi setenvif > /dev/null
                           a2enconf php7.0-fpm > /dev/null"

echo "$($_ORANGE_)Enable apache2 mods$($_WHITE_)"
lxc exec cloud -- bash -c "a2enmod rewrite > /dev/null
                           a2enmod headers env dir mime > /dev/null"

echo "$($_ORANGE_)Tuning opcache (php7) conf$($_WHITE_)"
lxc exec cloud -- bash -c "sed -i                                                                              \
    -e 's/;opcache.enable=0/opcache.enable=1/'                                      \
    -e 's/;opcache.enable_cli=0/opcache.enable_cli=1/'                              \
    -e 's/;opcache.interned_strings_buffer=4/opcache.interned_strings_buffer=8/'    \
    -e 's/;opcache.max_accelerated_files=2000/opcache.max_accelerated_files=10000/' \
    -e 's/;opcache.memory_consumption=64/opcache.memory_consumption=128/'           \
    -e 's/;opcache.save_comments=1/opcache.save_comments=1/'                        \
    -e 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=1/'                    \
    /etc/php/7.0/fpm/php.ini"

echo "$($_ORANGE_)Restart FPM$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl restart php7.0-fpm.service"

echo "$($_ORANGE_)Restart apache2$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl restart apache2.service"

echo "$($_ORANGE_)Test Apache + PHP with FPM$($_WHITE_)"
lxc exec cloud -- bash -c "cat << EOF > /var/www/html/phpinfo.php
<?php
phpinfo();
EOF"

lxc exec cloud -- bash -c 'if curl -s 127.0.0.1/phpinfo.php|grep -q php-fpm; then
    echo -e "\n\033[32m ** FPM OK **\033[00m\n"
else
    >&2 echo -e "\033[31m==================== ERROR  ====================\033[00m"
    >&2 echo -e "\033[31m==================== FPM HS ====================\033[00m"
    exit 1
fi'

lxc exec cloud -- bash -c "rm -f /var/www/html/phpinfo.php"

echo "$($_ORANGE_)apache2 listen only in Private IP$($_WHITE_)"
lxc exec cloud -- bash -c "echo 'Listen $IP_cloud_PRIV:80' > /etc/apache2/ports.conf"

echo "$($_ORANGE_)Download and uncompress Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "wget -q https://download.nextcloud.com/server/releases/nextcloud-13.0.1.tar.bz2 -O /tmp/nextcloud.tar.bz2"
lxc exec cloud -- bash -c "tar xaf /tmp/nextcloud.tar.bz2 -C /var/www/"
lxc exec cloud -- bash -c "rm -f /tmp/nextcloud.tar.bz2"

echo "$($_ORANGE_)Update directory privileges$($_WHITE_)"
lxc exec cloud -- bash -c "
    chown -R www-data:www-data /var/www/nextcloud/
    mkdir -p /var/log/nextcloud
    chown -R www-data:www-data /var/log/nextcloud
    "

echo "$($_ORANGE_)Create Vhost apache for Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c 'cat << "EOF" > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName __FQDN__

    ServerAdmin __MAIL_ADMIN__
    DocumentRoot /var/www/nextcloud

    # Autorisation des réécritures
    RewriteEngine  on

    # Tunning des logs de sortie
    LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" \"%{Host}i\"" MyFormat
    CustomLog ${APACHE_LOG_DIR}/cloud_access.log MyFormat

</VirtualHost>

<Directory /var/www/nextcloud>

    Options +FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_dav.c>
        Dav off
    </IfModule>

    SetEnv HOME /var/www/nextcloud
    SetEnv HTTP_HOME /var/www/nextcloud

</Directory>
EOF'

echo "$($_ORANGE_)Update FQDN$($_WHITE_)"
lxc exec cloud -- bash -c "sed -i -e 's/__FQDN__/$FQDN/' -e 's/__MAIL_ADMIN__/$EMAIL_CERTBOT/' /etc/apache2/sites-available/nextcloud.conf"

echo "$($_ORANGE_)Disable Default Vhost and enable nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "a2dissite 000-default > /dev/null
                           a2ensite nextcloud.conf > /dev/null"

echo "$($_ORANGE_)apache2 configtest$($_WHITE_)"
lxc exec cloud -- bash -c "apache2ctl configtest"

echo "$($_ORANGE_)Reload apache2$($_WHITE_)"
lxc exec cloud -- bash -c "systemctl reload apache2"

echo "$($_ORANGE_)Nextcloud installation$($_WHITE_)"
lxc exec cloud -- bash -c "occ maintenance:install --database 'mysql' --database-host '$IP_mariadb_PRIV' --database-name 'nextcloud'  --database-user 'nextcloud' --database-pass '$MDP_nextcoud' --admin-user '$NEXTCLOUD_admin_user' --admin-pass '$NEXTCLOUD_admin_password' --data-dir='/srv/data-cloud'"

echo "$($_ORANGE_)Tune Nextcloud conf$($_WHITE_)"
lxc exec cloud -- bash -c "occ config:system:set trusted_domains 0 --value='$FQDN'
                           occ config:system:set overwrite.cli.url --value='$FQDN'
                           # French conf
                           occ config:system:set default_language --value='fr'
                           occ config:system:set force_language   --value='fr'
                           occ config:system:set htaccess.RewriteBase --value='/'
                           occ config:system:set logtimezone --value='Europe/Paris'
                           # Redis
                           occ config:system:set memcache.local --value='\\OC\\Memcache\\Redis'
                           occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis'
                           occ config:system:set redis host --value='localhost'
                           occ config:system:set redis port --value='6379'
                           # Log
                           occ config:system:set loglevel --value='2'
                           occ config:system:set logfile --value='/var/log/nextcloud/nextcloud.log'
                           # 100Mo ( 100 * 1024 * 1024 ) = 104857600 byte
                           occ config:system:set log_rotate_size --value=$(( 100 * 1024 * 1024 ))
                           "

echo "$($_ORANGE_)Update .htaccess$($_WHITE_)"
lxc exec cloud -- bash -c "occ maintenance:update:htaccess > /dev/null"

echo "$($_ORANGE_)Install app in Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "occ app:install calendar
                           occ app:enable  calendar
                           occ app:enable  admin_audit
                           occ app:install contacts
                           occ app:enable  contacts
                           occ app:install announcementcenter
                           occ app:enable  announcementcenter
                           occ app:install richdocuments
                           occ app:enable  richdocuments
                           "

echo "$($_ORANGE_)configure SMTP in Nextcloud$($_WHITE_)"
lxc exec cloud -- bash -c "occ config:system:set mail_smtpmode --value='smtp'
                           occ config:system:set mail_smtpauthtype --value='LOGIN'
                           occ config:system:set mail_from_address --value='cloud'
                           occ config:system:set mail_domain --value='$FQDN'
                           occ config:system:set mail_smtphost --value='$IP_smtp_PRIV'
                           occ config:system:set mail_smtpport --value='25'
                           "

################################################################################

echo "$($_ORANGE_)Add Let's Encrypt chain.pem (CA Root Certificates) in Nextcloud$($_WHITE_)"
chain_pem="$(lxc exec rvprx -- cat /etc/letsencrypt/live/$FQDN/chain.pem)"
lxc exec cloud -- bash -c "cat << 'EOF' >> /var/www/nextcloud/resources/config/ca-bundle.crt

Let's Encrypt
=============
$chain_pem
EOF
"

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec cloud -- bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart cloud

echo "$($_GREEN_)END cloud$($_WHITE_)"
echo ""

