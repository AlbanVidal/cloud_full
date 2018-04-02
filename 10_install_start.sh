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

# If vars file exist, source
if [ -f 00_VARS ]; then
    . 00_VARS
else
    echo ""
    echo "$($_RED_)File « 00_VARS » don't exist$($_WHITE_)"
    echo "$($_ORANGE_)Please reply to the next questions$($_WHITE_)"
    echo ""
    echo -n "$($_GREEN_)FQDN:$($_WHITE_) "
    read FQDN
    echo -n "$($_GREEN_)Collabora FQDN:$($_WHITE_) "
    read FQDN_collabora
    echo -n "$($_GREEN_)Test email (to test Postfix after conf):$($_WHITE_) "
    read MAIL_TEST
    echo -n "$($_GREEN_)Certbort Alert email:$($_WHITE_) "
    read EMAIL_CERTBOT
    echo -n "$($_GREEN_)Nextcloud Admin User:$($_WHITE_) "
    read NEXTCLOUD_admin_user
    echo -n "$($_GREEN_)Nextcloud Admin Password:$($_WHITE_) "
    read -rs NEXTCLOUD_admin_password

    cat << EOF > 00_VARS
FQDN="$FQDN"
FQDN_collabora="$FQDN_collabora"
MAIL_TEST="$MAIL_TEST"
EMAIL_CERTBOT="$EMAIL_CERTBOT"
NEXTCLOUD_admin_user="$NEXTCLOUD_admin_user"
NEXTCLOUD_admin_password="$NEXTCLOUD_admin_password"
EOF

    echo ""
    echo "$($_ORANGE_)File « 00_VARS » generated$($_WHITE_)"
    echo ""

fi

# Load Network Vars
. 01_NETWORK_VARS

################################################################################
#### HOST CONFIGURATION

# Update apt package list
echo "$($_ORANGE_)Update apt package list$($_WHITE_)"
apt-get update > /dev/null

#############
echo "$($_ORANGE_)Upgrading system packages$($_WHITE_)"
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null


# Nat post 80 and 443 => RVPRX
# Enable Masquerade and NAT rules
echo "$($_ORANGE_)Install: iptables-persistent$($_WHITE_)"
DEBIAN_FRONTEND=noninteractive apt-get -y install iptables-persistent > /dev/null
echo "$($_ORANGE_)Enable Masquerade and NAT rules$($_WHITE_)"
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

echo "$($_ORANGE_)Disable IPv6 on all connexion$($_WHITE_)"
cat << EOF > /etc/sysctl.d/81-disable-ipv6.conf
# Disable IPv6 on all connexion
net.ipv6.conf.all.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/81-disable-ipv6.conf

##### DEBIAN
echo "$($_ORANGE_)Install: snapd, udev, btrfs-tools and LXD with snapd$($_WHITE_)"
DEBIAN_FRONTEND=noninteractive apt-get -y install snapd udev btrfs-tools > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get clean
snap install lxd > /dev/null

##### UBUNTU
## Install LXD package
#apt-get install lxd-client/trusty-backports
#apt-get install lxd/trusty-backports
##apt-get install lxd

echo "$($_GREEN_)LXD is installed$($_WHITE_)"
echo ""
echo "$($_RED_)Please logout/login in bash to prevent snap bug and start script :$($_WHITE_)"
echo "$($_GREEN_)11_install_next.sh$($_WHITE_)"

