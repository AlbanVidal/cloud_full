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

#### MariaDB
echo "$($_GREEN_)BEGIN mariadb$($_WHITE_)"
echo "$($_ORANGE_)Update, upgrade and packages$($_WHITE_)"
lxc exec mariadb -- apt-get update > /dev/null
lxc exec mariadb -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null"
lxc exec mariadb -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install vim apt-utils > /dev/null"
 
echo "$($_ORANGE_)Install MariaDB serveur$($_WHITE_)"
lxc exec mariadb -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server > /dev/null"

echo "$($_ORANGE_)Secure MariaDB (like mysql_secure_installation)$($_WHITE_)"
cat << EOF > /tmp/lxd_mariadb_secure_installation
#!/bin/bash
# Delete anonymous users
mysql -e "DELETE FROM mysql.user WHERE User='';"
# Ensure the root user can not log in remotely
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
# Remove the test database
mysql -e "DROP DATABASE IF EXISTS test;
          DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"

# Make our changes take effect
mysql -e "FLUSH PRIVILEGES"
EOF

lxc file push --mode 500 /tmp/lxd_mariadb_secure_installation mariadb/tmp/lxd_mariadb_secure_installation
exec mariadb -- bash -c "/tmp/lxd_mariadb_secure_installation"

echo "$($_ORANGE_)Create nextcloud database and user$($_WHITE_)"
MDP_nextcoud="$(cat /tmp/lxc_nextcloud_password)"
cat << EOF > /tmp/lxd_mariadb_create_database_and_user
#!/bin/bash
mysql <<< '
    CREATE DATABASE nextcloud;
    GRANT ALL PRIVILEGES ON nextcloud.* TO "nextcloud"@"$IP_cloud_PRIV" IDENTIFIED BY "'$MDP_nextcoud'";
    FLUSH PRIVILEGES;
'
EOF

