#!/bin/bash

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

# Path of git repository
# ../
GIT_PATH="$(realpath ${0%/*/*})"

# Load Vars
source $GIT_PATH/config/00_VARS

# Load Network Vars
source $GIT_PATH/config/01_NETWORK_VARS

# Load Resources Vars
source $GIT_PATH/config/02_RESOURCES_VARS

################################################################################

#### SMTP
echo "$($_GREEN_)BEGIN smtp$($_WHITE_)"
echo "$($_ORANGE_)Install specific packages$($_WHITE_)"
lxc exec smtp -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install postfix > /dev/null"

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
    -e "s#_myhostname_#$FQDN#"                 \
    -e "s#_PRIVATE_NETWORK_#$PRIVATE_NETWORK#" \
    -e "s#_IP_SMTP_#$IP_smtp_PRIV#"            \
    /tmp_lxd_smtp_etc_postfix_main.cf

lxc file push /tmp_lxd_smtp_etc_postfix_main.cf smtp/etc/postfix/main.cf
lxc exec smtp -- bash -c "echo $FQDN > /etc/mailname
                          systemctl restart postfix
                          echo Test SMTP $FQDN|mail -s 'Test SMTP $FQDN' $NEXTCLOUD_admin_email
                          "

################################################################################

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec smtp -- bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart smtp --force

echo "$($_ORANGE_)Set CPU and Memory limits$($_WHITE_)"
lxc profile add smtp $LXC_PROFILE_smtp_CPU
lxc profile add smtp $LXC_PROFILE_smtp_MEM

echo "$($_GREEN_)END smtp$($_WHITE_)"
echo ""

