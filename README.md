Full personal cloud
===================

**Automated deploy your private cloud**

Working on:
+ [x] Debian 9 (stretch)
+ [ ] Debian 10 (buster) ==> Test in progress (see Bugs, end of ReadMe)

This scripts deploy this solution :
+ Private cloud: **Nextcloud**
+ Online Office: **Collabora Online**
+ Databases for Nextcloud: **MariaDB**
+ Reverse-Proxy in front of Nextcloud and Collabora: **Nginx**
+ Nextcloud mail notifications: **postfix**

The following features is enabled :
+ Auto generate SSL certificate with **Let's Encrypt**
+ Isolation betwen components with **lxd**

----------------------------------------

# Files description

+ `0*` files contain variables used by scripts
+ `10_install_start.sh` file is used to configure host (Upgrade, install necessary packages)
+ `11_install_next.sh` file is used to configure all containers. This script launch all `2*.sh` scripts
+ `2*.sh` scripts is used to configure specific container, they are used by `11_install_next.sh` script

----------------------------------------

# Usage

## Prerequisites

+ Email address to Nextcloud password recovery and Let's Encrypt alerts
+ Your personal domain name
+ PTR DNS record for send mail

## Preparation

You need to install `git` package in your host, and clone this repository:

```bash
apt -y install git
git clone https://github.com/AlbanVidal/cloud_full.git
```

## Configuration

Launch this first script to set your personnal variables (FQDN, email, Cloud Admin user...) and configure host:

```bash
# Upgrade, install necessary packages (snap, LXD with snap...)
./10_install_start.sh
```

## Installation

Launch this second script create and autoconfigure all containers:


```bash
./11_install_next.sh
```

----------------------------------------
# Variables

## Network variables

You can change change network settings of LXD containers in file `01_NETWORK_VARS`

## Editables variables

You can change this defaults variables in file `03_OTHER_VARS`

+ Default MAX upload file size (default: 5GB)
+ Default Language (default: French)
+ Time Zone (default: Europe/Paris)
+ Nextcloud Log rotate size (default: 100MB)
+ Nextcloud data directory (default: /srv/data-cloud)

----------------------------------------

# Bugs

**Debian 10 fails:**
+ mariadb with systemd (ownership in unprivileged container)
+ redis-server with systemd (ownership in unprivileged container)
