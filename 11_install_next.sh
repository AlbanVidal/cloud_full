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

# Load Resources Vars
. 02_RESOURCES_VARS

# Load Other vars 
# - LXD_DEPORTED_DIR
# - DEBIAN_RELEASE
# - LXD_DEFAULT_STORAGE_TYPE
. 03_OTHER_VARS

################################################################################

# Exit if LXD is not installed
if ! which lxd >/dev/null;then
    echo "$($_RED_)LXD is not installed$($_WHITE_)"
    exit 1
fi

# LXD INIT
echo "$($_ORANGE_)LXD initialization$($_WHITE_)"

# Test if LXD_INIT=true (see 03_OTHER_VARS to edit)
if ! $LXD_INIT; then
    echo "$($_ORANGE_)You have choose to not configure lxd$($_WHITE_)"
else
    # Initializing of lxd
    cat << EOF | lxd init --preseed
# Daemon settings
config:
  images.auto_update_interval: 15

# Storage pools
storage_pools:
- name: default
  driver: $LXD_DEFAULT_STORAGE_TYPE

# Network devices
networks:
- name: lxdbrEXT
  type: bridge
  config:
    ipv4.address: $IP_LXD/$CIDR
    ipv4.nat: "true"
    ipv4.dhcp: "true"
    ipv4.dhcp.ranges: $lxdbrEXT_DHCP_RANGE
    ipv6.address: none

- name: lxdbrINT
  type: bridge
  config:
    ipv4.address: $IP_LXD_PRIV/$CIDR
    ipv4.nat: "false"
    ipv4.dhcp: "false"
    ipv6.address: none

# Profiles
profiles:

- name: default
  description: "Default Net and storage"
  devices:
    ethPublic:
      name: eth0
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
      name: ethPrivate
      nictype: bridged
      parent: lxdbrINT
      type: nic

- name: cpu-1
  description: "1 CPU"
  config:
    limits.cpu: "1"

- name: cpu-2
  description: "2 CPU"
  config:
    limits.cpu: "2"

- name: cpu-4
  description: "4 CPU"
  config:
    limits.cpu: "4"

- name: ram-256
  description: "256MB RAM"
  config:
    limits.memory: 256MB

- name: ram-512
  description: "512MB RAM"
  config:
    limits.memory: 512MB

- name: ram-1024
  description: "1GB RAM"
  config:
    limits.memory: 1GB

- name: ram-2048
  description: "2GB RAM"
  config:
    limits.memory: 2GB

- name: ram-4096
  description: "4GB RAM"
  config:
    limits.memory: 4GB
EOF
fi

# TEMPLATE interfaces containers
cat << EOF > /tmp/lxd_interfaces_TEMPLATE
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address _IP_PUB_/_CIDR_
    gateway $IP_LXD

auto ethPrivate
iface ethPrivate inet static
    address _IP_PRIV_/_CIDR_
EOF

# TEMPLATE resolv.conf (see 01_NETWORK_VARS to change nameserver)
cat << EOF > /tmp/lxd_resolv.conf
$RESOLV_CONF
EOF

################################################################################
#
# Create template container

lxc launch images:debian/$DEBIAN_RELEASE z-template --profile default --profile privNet
#lxc exec z-template -- bash -c "
#                                echo -e 'auto lo\\niface lo inet loopback\\n\\nauto ethPublic\\niface ethPublic inet dhcp' > /etc/network/interfaces
#                               "
#lxc restart z-template

echo "$($_ORANGE_)Wait dhcp...$($_WHITE_)"
sleep 5

################################################################################
#
# Configure template container

echo "$($_ORANGE_)Container TEMPLATE: Update, upgrade and install common packages$($_WHITE_)"

PACKAGES="vim apt-utils bsd-mailx unattended-upgrades apt-listchanges logrotate postfix"

if [ "$DEBIAN_RELEASE" == "stretch" ] ; then
    lxc exec z-template -- bash -c "echo 'deb http://ftp.fr.debian.org/debian stretch-backports main' > /etc/apt/sources.list.d/stretch-backports.list"
fi

lxc exec z-template -- bash -c "
    apt-get update > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null
    # Unattended configuration
    sed -i \
        -e 's#^//Unattended-Upgrade::Mail .*#Unattended-Upgrade::Mail \"$TECH_ADMIN_EMAIL\";#' \
        -e 's#^//Unattended-Upgrade::MailOnlyOnError .*#Unattended-Upgrade::MailOnlyOnError \"true\";#' \
        /etc/apt/apt.conf.d/50unattended-upgrades
    # Tune logrotate cron (add -f)
    echo -e '#!/bin/sh\ntest -x /usr/sbin/logrotate || exit 0\n/usr/sbin/logrotate -f /etc/logrotate.conf' > /etc/cron.daily/logrotate
    # Disable IPv6
    echo 'net.ipv6.conf.all.disable_ipv6 = 1' > /etc/sysctl.d/98-disable-ipv6.conf
"

# Postfix default conf file
# Copy file in tmp becose « snap » is isoled, can't acess to root dir
cp /etc/postfix/main.cf /tmp/template_postfix_main.cf
lxc file push /tmp/template_postfix_main.cf z-template/etc/postfix/main.cf

# Copy /etc/crontab for Send crontab return to admin (TECH_ADMIN_EMAIL)
lxc file push /etc/crontab z-template/etc/crontab

lxc stop z-template --force

################################################################################

# Create all container from template
echo "$($_ORANGE_)Create and network configuration for all containers$($_WHITE_)"

CT_LIST="smtp rvprx mariadb cloud collabora"

for CT in $CT_LIST ; do
    echo "$($_ORANGE_)Create ${CT}...$($_WHITE_)"
    lxc copy z-template ${CT}
    lxc start ${CT}
    IP_PUB="IP_${CT}"
    IP_PRIV="IP_${CT}_PRIV"
    sed -e "s/_IP_PUB_/${!IP_PUB}/" -e "s/_IP_PRIV_/${!IP_PRIV}/" -e "s/_CIDR_/$CIDR/" /tmp/lxd_interfaces_TEMPLATE > /tmp/lxd_interfaces_${CT}
    lxc file push /tmp/lxd_interfaces_${CT} ${CT}/etc/network/interfaces
    lxc file push /tmp/lxd_resolv.conf ${CT}/etc/resolv.conf
    lxc restart $CT --force
done

################################################################################

# Create and attach deported directory
echo "$($_ORANGE_)Create and attach deported directory ($LXD_DEPORTED_DIR/…)$($_WHITE_)"
## RVPRX
mkdir -p \
    $LXD_DEPORTED_DIR/rvprx/etc/nginx        \
    $LXD_DEPORTED_DIR/rvprx/etc/letsencrypt  \
lxc config device add rvprx shared-rvprx disk path=/srv/lxd source=$LXD_DEPORTED_DIR/rvprx/

## Cloud
mkdir -p \
    $LXD_DEPORTED_DIR/cloud/var/www
lxc config device add cloud shared-cloud disk path=/srv/lxd source=$LXD_DEPORTED_DIR/cloud/

# Set mapped UID and GID to LXD deported directory
echo "$($_ORANGE_)Set mapped UID and GID to LXD deported directory ($LXD_DEPORTED_DIR)$($_WHITE_)"
chown -R 1000000:1000000 $LXD_DEPORTED_DIR/

################################################################################
#### CONTAINER CONFIGURATION
echo ""
echo "$($_GREEN_)CONTAINER CONFIGURATION$($_WHITE_)"
echo ""

############################################################
#### SMTP
./21_configure_smtp.sh

############################################################
#### RVPRX
./22_configure_rvprx.sh

############################################################
#### MariaDB

# Generate nextcloud database password
MDP_nextcoud=$(openssl rand -base64 32)
echo "$MDP_nextcoud" > /tmp/lxc_nextcloud_password

./23_configure_mariadb.sh

############################################################
#### CLOUD
./24_configure_cloud.sh

# Delete nextcloud database password
rm -f /tmp/lxc_nextcloud_password

############################################################
#### COLLABORA
./25_configure_collabora.sh

################################################################################
