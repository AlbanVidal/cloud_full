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

#### COLLABORA
echo "$($_GREEN_)BEGIN collabora$($_WHITE_)"
echo "$($_ORANGE_)Update, upgrade and packages$($_WHITE_)"
lxc exec collabora -- apt-get update > /dev/null
lxc exec collabora -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null"
lxc exec collabora -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim apt-utils > /dev/null"
 
echo "$($_ORANGE_)Add Docker repo and install Docker$($_WHITE_)"
lxc exec collabora -- bash -c "apt-get -y install curl apt-transport-https gnupg gnupg2 gnupg1 > /dev/null
                               curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
                               echo -e '\n# Depôt Docker\ndeb https://download.docker.com/linux/debian stretch stable' > /etc/apt/sources.list.d/docker.list
                               apt-get update > /dev/null
                               apt-get -y install docker-ce > /dev/null
                               "

echo "$($_ORANGE_)Tuning Docker for Debian$($_WHITE_)"
lxc exec collabora -- bash -c "mkdir /etc/systemd/system/docker.service.d
                               cat << EOF > /etc/systemd/system/docker.service.d/DeviceMapper.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --storage-driver=devicemapper -H fd://
EOF
"

echo "$($_ORANGE_)Restart Docker$($_WHITE_)"
lxc exec collabora -- bash -c "systemctl daemon-reload
                               systemctl restart docker
                               "

echo "$($_ORANGE_)pull collabora$($_WHITE_)"
lxc exec collabora -- bash -c "docker pull collabora/code"

# Need to add two « \ » between « . »
DOMAIN=$(echo $FQDN| sed 's#\.#\\\\.#g')
lxc exec collabora -- bash -c "docker run -t -d -p $IP_collabora_PRIV:9980:9980 -e 'domain=$DOMAIN' --restart always --cap-add MKNOD collabora/code"

