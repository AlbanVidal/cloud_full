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
GIT_PATH="$(realpath ${0%/*/*})"

# Load Vars
source $GIT_PATH/config/00_VARS

# Load Network Vars
source $GIT_PATH/config/01_NETWORK_VARS

# Load Resources Vars
source $GIT_PATH/config/02_RESOURCES_VARS

################################################################################

#### MariaDB

# Test if Nextcloud database password is set
if [ ! -f /tmp/lxc_nextcloud_password ] ; then
    echo "$($_RED_)You need to create « /tmp/lxc_nextcloud_password » with nextcloud user passord$($_WHITE_)"
    exit 1
fi
MDP_nextcoud="$(cat /tmp/lxc_nextcloud_password)"

echo "$($_GREEN_)BEGIN mariadb$($_WHITE_)"

# Install MariaDB serveur
echo "$($_ORANGE_)Install MariaDB serveur$($_WHITE_)"
lxc exec mariadb -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server > /dev/null"

# Secure MariaDB (like mysql_secure_installation

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
lxc exec mariadb -- bash -c "/tmp/lxd_mariadb_secure_installation"

# Create nextcloud database and user

echo "$($_ORANGE_)Create nextcloud database and user$($_WHITE_)"
cat << EOF > /tmp/lxd_mariadb_create_database_and_user
#!/bin/bash
mysql <<< '
    CREATE DATABASE nextcloud;
    GRANT ALL PRIVILEGES ON nextcloud.* TO "nextcloud"@"$IP_cloud_PRIV" IDENTIFIED BY "'$MDP_nextcoud'";
    FLUSH PRIVILEGES;
'
EOF

lxc file push --mode 500 /tmp/lxd_mariadb_create_database_and_user mariadb/tmp/lxd_mariadb_create_database_and_user
lxc exec mariadb -- bash -c "/tmp/lxd_mariadb_create_database_and_user"

# Change MariaDB Bind Address

echo "$($_ORANGE_)Change MariaDB Bind Address$($_WHITE_)"

lxc exec mariadb -- bash -c "sed -i 's/bind-address.*/bind-address = $IP_mariadb_PRIV/' /etc/mysql/mariadb.conf.d/50-server.cnf"

echo "$($_ORANGE_)Restart MariaDB$($_WHITE_)"
lxc exec mariadb -- bash -c "systemctl restart mariadb"

################################################################################

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec mariadb -- bash -c "apt-get clean"

################################################################################

# Copy MySQL dump script
lxc file push $GIT_PATH/templates/mariadb/mysql-auto-dump mariadb/usr/local/bin/

################################################################################

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart mariadb --force

echo "$($_ORANGE_)Set CPU and Memory limits$($_WHITE_)"
lxc profile add mariadb $LXC_PROFILE_mariadb_CPU
lxc profile add mariadb $LXC_PROFILE_mariadb_MEM

echo "$($_GREEN_)END mariadb$($_WHITE_)"
echo ""

