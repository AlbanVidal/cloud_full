#!/bin/bash

# TODO
# - logrotate (all CT)
# - iptables isolateur: Deny !80 !443

# If vars file exist, source
if [ -f 00_VARS ]; then
    . 00_VARS
else
    > 00_VARS
    echo "Please reply to the next questions"
    echo ""
    echo -n "FQDN : "
    read FQDN
    echo $FQDN >> 00_VARS
    read FQDN_collabora
    echo $FQDN_collabora >> 00_VARS
    read MAIL_TEST
    echo $MAIL_TEST >> 00_VARS
    read EMAIL_CERTBOT
    echo $EMAIL_CERTBOT >> 00_VARS
fi
################################################################################
#### EDITABLE VARS
#
CIDR=24
#
# External Network (Internet)
IP_LXD="172.16.0.1"
IP_cloud="172.16.0.2"
IP_collabora="172.16.0.3"
IP_mariadb="172.16.0.4"
IP_rvprx="172.16.0.5"
IP_smtp="172.16.0.6"
#
# Internal Network (Private)
IP_cloud_PRIV="172.17.0.2"
IP_collabora_PRIV="172.31.0.3"
IP_mariadb_PRIV="172.17.0.4"
IP_rvprx_PRIV="172.17.0.5"
IP_smtp_PRIV="172.17.0.6"
#
# Private Network (for Postfix)
PRIVATE_NETWORK="172.17.0.0/24"
#
################################################################################

################################################################################
#### HOST CONFIGURATION

# Update apt package list
apt-get update

#############
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade


# Nat post 80 and 443 => RVPRX
# Enable Masquerade and NAT rules
DEBIAN_FRONTEND=noninteractive apt-get -y install iptables-persistent
cat << EOF > /etc/iptables/rules.v4
################################################################################
##########                          TABLE NAT                         ########## 
################################################################################
*nat
####
:PREROUTING ACCEPT [0:0]
# Internet Input (PREROUTING)
-N zone_wan_PREROUTING
-A PREROUTING -i eth0 -j zone_wan_PREROUTING -m comment --comment "Internet Input PREROUTING"
# NAT 80 > RVPRX (nginx)
-A zone_wan_PREROUTING -p tcp -m tcp --dport 80 -j DNAT --to-destination $IP_rvprx:80 -m comment --comment "Routing port 80 > RVPRX - TCP"
-A zone_wan_PREROUTING -p udp -m udp --dport 80 -j DNAT --to-destination $IP_rvprx:80 -m comment --comment "Routing port 80 > RVPRX - UDP"
# NAT 443 > RVPRX (nginx)
-A zone_wan_PREROUTING -p tcp -m tcp --dport 443 -j DNAT --to-destination $IP_rvprx:443 -m comment --comment "Routing port 443 > RVPRX - TCP"
-A zone_wan_PREROUTING -p udp -m udp --dport 443 -j DNAT --to-destination $IP_rvprx:443 -m comment --comment "Routing port 443 > RVPRX - UDP"
COMMIT
EOF
iptables-restore /etc/iptables/rules.v4

# Disable IPv6 on all connexion
cat << EOF > /etc/sysctl.d/81-disable-ipv6.conf
# Disable IPv6 on all connexion
net.ipv6.conf.all.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/81-disable-ipv6.conf

##### DEBIAN
DEBIAN_FRONTEND=noninteractive apt-get -y install snapd udev
DEBIAN_FRONTEND=noninteractive apt-get clean
snap install lxd

##### UBUNTU
## Install LXD package
#apt-get install lxd-client/trusty-backports
#apt-get install lxd/trusty-backports
##apt-get install lxd

# LXD INIT
cat << EOF | lxd init --preseed
# Daemon settings
config:
  images.auto_update_interval: 15

# Storage pools
storage_pools:
- name: default
  driver: dir

# Network devices
networks:
- name: lxdbrEXT
  type: bridge
  config:
    ipv4.address: $IP_LXD/$CIDR
    ipv4.nat: "true"
    ipv4.dhcp: "false"
    ipv6.address: none

- name: lxdbrINT
    type: bridge
  config:
    ipv4.address: none
    ipv4.nat: "false"
    ipv4.dhcp: "false"
    ipv6.address: none

# Profiles
profiles:
- name: default
  description: "Default Net and storage"
  devices:
    ethPublic:
      nictype: bridged
      parent: lxdbrEXT
      type: nic
    root:
      path: /
      pool: default
      type: disk
- name: privNet
  description: "Internal (backend) Network"
  devices:
    ethPrivate:
      nictype: bridged
      parent: lxdbrINT
      type: nic
- name: 1c1024m
  description: "1 CPU and 1024MB RAM"
  config:
    limits.memory: 1GB
    limits.cpu: "1"
- name: 1c256m
  description: "1 CPU and 256MB RAM"
  config:
    limits.memory: 256MB
    limits.cpu: "1"
EOF

# TEMPLATE interfaces containers
cat << EOF > /tmp/lxd_interfaces_TEMPLATE
auto lo
iface lo inet loopback

auto ethPublic
iface ethPublic inet static
    address _IP_PUB_/_CIDR_
    gateway $IP_LXD

auto ethPrivate
iface ethPrivate inet static
    address _IP_PRIV_/_CIDR_
EOF

# CT 1 - CLOUD
lxc launch images:debian/stretch cloud --profile default --profile privNet --profile 1c256m
sed -e "s/_IP_PUB_/$IP_cloud/" -e "s/_IP_PRIV_/$IP_cloud_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_cloud
lxc file push /tmp/lxd_interfaces_cloud cloud/etc/network/interfaces
lxc restart cloud

# CT 2 - COLLABORA
lxc launch images:debian/stretch collabora --profile default --profile privNet --profile 1c256m
sed -e "s/_IP_PUB_/$IP_collabora/" -e "s/_IP_PRIV_/$IP_collabora_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_collabora
lxc file push /tmp/lxd_interfaces_collabora collabora/etc/network/interfaces
lxc restart collabora

# CT 3 - MariaDB
lxc launch images:debian/stretch mariadb --profile default --profile privNet --profile 1c256m
sed -e "s/_IP_PUB_/$IP_mariadb/" -e "s/_IP_PRIV_/$IP_mariadb_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_mariadb
lxc file push /tmp/lxd_interfaces_mariadb mariadb/etc/network/interfaces
lxc restart mariadb

# CT 4 - RVPRX
lxc launch images:debian/stretch rvprx --profile default --profile privNet --profile 1c256m
sed -e "s/_IP_PUB_/$IP_rvprx/" -e "s/_IP_PRIV_/$IP_rvprx_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_rvprx
lxc file push /tmp/lxd_interfaces_rvprx rvprx/etc/network/interfaces
lxc restart rvprx

# CT 5 - SMTP
lxc launch images:debian/stretch smtp --profile default --profile privNet --profile 1c256m
sed -e "s/_IP_PUB_/$IP_smtp/" -e "s/_IP_PRIV_/$IP_smtp_PRIV/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_smtp
lxc file push /tmp/lxd_interfaces_smtp smtp/etc/network/interfaces
lxc restart smtp

################################################################################
#### CONTAINER CONFIGURATION

# SMTP
lxc exec smtp -- apt-get update
lxc exec smtp -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"
lxc exec smtp -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim postfix bsd-mailx"

# Postfix conf (create, push and reload)
cat << 'EOF' > /tmp_lxd_smtp_etc_postfix_main.cf
smtpd_banner = $myhostname ESMTP $mail_name (Debian/GNU)
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache
smtpd_recipient_restrictions = permit_sasl_authenticated,
  permit_mynetworks,
  reject_unauth_destination,
  reject_unknown_sender_domain,
  reject_unknown_client,
  permit

smtpd_sasl_local_domain = $myhostname

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = _myhostname_
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $myhostname, _myhostname_, localhost.localdomain, localhost
relayhost =
mynetworks = 127.0.0.0/8 _PRIVATE_NETWORK_
mailbox_command = procmail -a "$EXTENSION"
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = 127.0.0.1, _IP_SMTP_
inet_protocols = ipv4
EOF
sed -i                                         \
    -e "s/_myhostname_/$FQDN/"                 \
    -e "s/_PRIVATE_NETWORK_/$PRIVATE_NETWORK/" \
    -e "s/_IP_SMTP_/$IP_smtp_PRIV/"            \
    /tmp_lxd_smtp_etc_postfix_main.cf
lxc file push /tmp_lxd_smtp_etc_postfix_main.cf smtp/etc/postfix/main.cf
lxc exec smtp -- bash -c "echo $FQDN > /etc/mailname"
lxc exec smtp -- systemctl restart postfix
lxc exec smtp -- bash -c "echo Test SMTP $FQDN|mail -s 'Test SMTP $FQDN' $MAIL_TEST"

############################################################
#### RVPRX
lxc exec rvprx -- bash -c 'echo "deb http://ftp.fr.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/stretch-backports.list'
lxc exec rvprx -- apt-get update
# Upgrade
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"
# Nginx - fail2ban
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim nginx iptables fail2ban"
# certbot for Nginx
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install python3-certbot-nginx/stretch-backports"
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
lxc exec rvprx -- bash -c "certbot certonly -n --agree-tos --email $EMAIL_CERTBOT --nginx -d $FQDN"
lxc exec rvprx -- bash -c "certbot certonly -n --agree-tos --email $EMAIL_CERTBOT --nginx -d $FQDN_collabora"

# RVPRX dhparam
lxc exec rvprx -- bash -c "openssl dhparam -out /etc/nginx/dhparam.pem 4096"

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
server {
    listen      80;
    server_name $FQDN_collabora;
    return 301  https://$FQDN_collabora\$request_uri;
}

server {
    listen      443 ssl;
    server_name $FQDN_collabora;

    # Let's Encrypt:
    ssl_certificate     /etc/letsencrypt/live/$FQDN_collabora/cert.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FQDN_collabora/privkey.pem;

    # Add common Conf:
    include /etc/nginx/RVPRX_common.conf;

    # LOGS
    gzip on;
    access_log /var/log/nginx/collabora_access.log;
    error_log  /var/log/nginx/collabora_error.log;

    location / { proxy_pass http://$IP_collabora_PRIV/; }
}
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_rvprx-collabora rvprx/etc/nginx/sites-available/rvprx-collabora

# Disable « default » vhost and enable new
lxc exec rvprx -- bash -c "rm -f /etc/nginx/sites-enabled/default"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-cloud /etc/nginx/sites-enabled/"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-collabora /etc/nginx/sites-enabled/"

# Fix server_names_hash_bucket_size
lxc exec rvprx -- bash -c "sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf"

# Test nginx conf and reload
lxc exec rvprx -- nginx -t
lxc exec rvprx -- nginx -s reload

## >> FAIL2BAN <<

############################################################
#### MariaDB
lxc exec mariadb -- apt-get update
lxc exec mariadb -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"

############################################################
#### CLOUD
lxc exec cloud -- apt-get update
lxc exec cloud -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"

############################################################
#### COLLABORA
lxc exec collabora -- apt-get update
lxc exec collabora -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade"

################################################################################
