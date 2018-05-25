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
# - DEBIAN_RELEASE
. 03_OTHER_VARS

################################################################################

#### COLLABORA
echo "$($_GREEN_)BEGIN collabora$($_WHITE_)"

echo "$($_GREEN_)Edit container security to enable privileged mode$($_WHITE_)"
lxc config set collabora security.privileged true
lxc restart collabora --force
sleep 5

echo "$($_ORANGE_)Add collaboraoffice repo and install collabora-online$($_WHITE_)"

# For ssl, see: https://github.com/CollaboraOnline/Docker-CODE/blob/master/scripts/start-libreoffice.sh
# For package install, see: https://www.collaboraoffice.com/code/

# Used to restrict FQDN able to call collabora
DOMAIN=$(echo $FQDN| sed 's#\.#\\\\.#g')
lxc exec collabora -- bash -c "
                               # Update and install basic packages
                               apt-get update > /dev/null
                               apt-get -y install gnupg apt-transport-https > /dev/null
                               # Add key and install packages
                               apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0C54D189F4BA284D > /dev/null
                               echo 'deb https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian9 ./' > /etc/apt/sources.list.d/CollaboraOnline.list
                               apt-get update > /dev/null
                               apt-get install -y loolwsd code-brand > /dev/null
                               
                               # Generate SSL certificates
                               mkdir -p /opt/ssl/
                               cd /opt/ssl/
                               mkdir -p certs/ca
                               openssl genrsa -out certs/ca/root.key.pem 2048 > /dev/null
                               openssl req -x509 -new -nodes -key certs/ca/root.key.pem -days 9131 -out certs/ca/root.crt.pem -subj '/C=DE/ST=BW/L=Stuttgart/O=Dummy Authority/CN=Dummy Authority' > /dev/null
                               mkdir -p certs/{servers,tmp}
                               mkdir -p 'certs/servers/localhost'
                               openssl genrsa -out 'certs/servers/localhost/privkey.pem' 2048 -key 'certs/servers/localhost/privkey.pem' > /dev/null
                               openssl req -key 'certs/servers/localhost/privkey.pem' -new -sha256 -out 'certs/tmp/localhost.csr.pem' -subj '/C=DE/ST=BW/L=Stuttgart/O=Dummy Authority/CN=localhost' > /dev/null
                               openssl x509 -req -in certs/tmp/localhost.csr.pem -CA certs/ca/root.crt.pem -CAkey certs/ca/root.key.pem -CAcreateserial -out certs/servers/localhost/cert.pem -days 9131 > /dev/null
                               mv certs/servers/localhost/privkey.pem /etc/loolwsd/key.pem
                               mv certs/servers/localhost/cert.pem /etc/loolwsd/cert.pem
                               mv certs/ca/root.crt.pem /etc/loolwsd/ca-chain.cert.pem
                               chmod 440 /etc/loolwsd/key.pem
                               chgrp lool /etc/loolwsd/key.pem
                               
                               # Tune trusted FQDN
                               sed -i '/Allow\\/deny wopi storage./a <host desc=\"Regex pattern of hostname to allow or deny.\" allow=\"true\">$DOMAIN</host>' /etc/loolwsd/loolwsd.xml
                               
                               systemctl restart loolwsd
                              "

################################################################################

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec collabora -- bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart collabora --force

echo "$($_ORANGE_)Set CPU and Memory limits$($_WHITE_)"
lxc profile add collabora $LXC_PROFILE_collabora_CPU
lxc profile add collabora $LXC_PROFILE_collabora_MEM

echo "$($_GREEN_)END collabora$($_WHITE_)"
echo ""

