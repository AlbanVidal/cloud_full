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

#### RVPRX
echo "$($_GREEN_)BEGIN rvprx$($_WHITE_)"
echo "$($_ORANGE_)Update, upgrade and packages$($_WHITE_)"
lxc exec rvprx -- bash -c 'echo "deb http://ftp.fr.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/stretch-backports.list'
lxc exec rvprx -- apt-get update > /dev/null
# Upgrade
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null"
# Nginx - fail2ban
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim apt-utils nginx iptables fail2ban > /dev/null"
# certbot for Nginx
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install python3-certbot-nginx/stretch-backports > /dev/null"
# conf file letsencrypt
cat << EOF > /tmp_lxd_rvprx_etc_letsencrypt_cli.ini
# Because we are using logrotate for greater flexibility, disable the
# internal certbot logrotation.
max-log-backups = 0
# Change size of Key
rsa-key-size = 4096
EOF
lxc file push /tmp_lxd_rvprx_etc_letsencrypt_cli.ini rvprx/etc/letsencrypt/cli.ini

# Generating certificates
echo "$($_ORANGE_)Generating certificates: $FQDN$($_WHITE_)"
lxc exec rvprx -- bash -c "certbot certonly -n --agree-tos --email $EMAIL_CERTBOT --nginx -d $FQDN,$FQDN_collabora > /dev/null"
#echo "$($_ORANGE_)Generating certificates: $FQDN_collabora$($_WHITE_)"
#lxc exec rvprx -- bash -c "certbot certonly -n --agree-tos --email $EMAIL_CERTBOT --nginx -d $FQDN_collabora > /dev/null"

# RVPRX dhparam
echo "$($_ORANGE_)Generating dhparam$($_WHITE_)"
lxc exec rvprx -- bash -c "openssl dhparam -out /etc/nginx/dhparam.pem 4096"

echo "$($_ORANGE_)Nginx: Conf, Vhosts and tuning$($_WHITE_)"

# RVPRX common conf
cat << 'EOF' > /tmp_lxd_rvprx_etc_nginx_RVPRX_common.conf
# SSL configuration :
# drop SSLv3 (POODLE vulnerability)
    ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
# Recommanded ciphers
    ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
# enables server-side protection from BEAST attacks
    ssl_prefer_server_ciphers on;
# enable session resumption to improve https performance
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 5m;
# Diffie-Hellman parameter for DHE ciphersuites, recommended 4096 bits
    ssl_dhparam /etc/nginx/dhparam.pem;

### force timeouts if one of backend is died ##
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;

### Set headers ####
    proxy_set_header        Accept-Encoding   "";
    proxy_set_header        Host            $host;
    proxy_set_header        X-Real-IP       $remote_addr;
    proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;

### Most PHP, Python, Rails, Java App can use this header ###
    proxy_set_header        X-Forwarded-Proto $scheme;
    add_header              Front-End-Https   on;

### By default we don't want to redirect it ####
    proxy_redirect     off;

# config to enable HSTS(HTTP Strict Transport Security) https://developer.mozilla.org/en-US/docs/Security/HTTP_Strict_Transport_Security
# to avoid ssl stripping https://en.wikipedia.org/wiki/SSL_stripping#SSL_stripping
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_RVPRX_common.conf rvprx/etc/nginx/RVPRX_common.conf

# RVPRX vhosts
cat << EOF > /tmp_lxd_rvprx_etc_nginx_rvprx-cloud
server {
    listen      80;
    server_name $FQDN;
    return 301  https://$FQDN\$request_uri;
}

server {
    listen      443 ssl;
    server_name $FQDN;

    # Let's Encrypt:
    ssl_certificate     /etc/letsencrypt/live/$FQDN/cert.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;

    # Add common Conf:
    include /etc/nginx/RVPRX_common.conf;

    # LOGS
    gzip on;
    access_log /var/log/nginx/cloud_access.log;
    error_log  /var/log/nginx/cloud_error.log;

    location / { proxy_pass http://$IP_cloud_PRIV/; }
}
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_rvprx-cloud rvprx/etc/nginx/sites-available/rvprx-cloud

cat << EOF > /tmp_lxd_rvprx_etc_nginx_rvprx-collabora
#server {
#    listen      80;
#    server_name $FQDN_collabora;
#    return 301  https://$FQDN_collabora\$request_uri;
#}

server {
    listen      443 ssl;
    server_name $FQDN_collabora;

    # Let's Encrypt:
    ssl_certificate     /etc/letsencrypt/live/$FQDN/cert.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;

    # Add common Conf:
    include /etc/nginx/RVPRX_common.conf;

    # LOGS
    gzip on;
    access_log /var/log/nginx/collabora_access.log;
    error_log  /var/log/nginx/collabora_error.log;

    # static files
    location ^~ /loleaflet {
        proxy_pass https://$IP_collabora_PRIV:9980;
        proxy_set_header Host \$http_host;
    }

    # WOPI discovery URL
    location ^~ /hosting/discovery {
        proxy_pass https://$IP_collabora_PRIV:9980;
        proxy_set_header Host \$http_host;
    }

   # main websocket
   location ~ ^/lool/(.*)/ws$ {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_set_header Host \$http_host;
       proxy_read_timeout 36000s;
   }
   
   # download, presentation and image upload
   location ~ ^/lool {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Host \$http_host;
   }
   
   # Admin Console websocket
   location ^~ /lool/adminws {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_set_header Host \$http_host;
       proxy_read_timeout 36000s;
   }
}
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_rvprx-collabora rvprx/etc/nginx/sites-available/rvprx-collabora

# Disable « default » vhost and enable new
lxc exec rvprx -- bash -c "rm -f /etc/nginx/sites-enabled/default"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-cloud /etc/nginx/sites-enabled/"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-collabora /etc/nginx/sites-enabled/"

# Fix server_names_hash_bucket_size
lxc exec rvprx -- bash -c "sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf"

# Set max file size to 10G
lxc exec rvprx -- bash -c "sed -i '/http {/a \\\t# Set max file size to 10G\\n\\tclient_max_body_size 10G;' /etc/nginx/nginx.conf |grep -C2 body_size"

# Test nginx conf and reload
lxc exec rvprx -- nginx -t
lxc exec rvprx -- nginx -s reload

## >> FAIL2BAN <<
 
################################################################################

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec rvprx -- bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart rvprx

echo "$($_GREEN_)END rvprx$($_WHITE_)"
echo ""

