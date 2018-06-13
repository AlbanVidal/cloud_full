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

+ `config/0*` files contain variables used by scripts
+ `10_install_start.sh` file is used to configure host (Upgrade, install necessary packages)
+ `11_install_next.sh` file is used to configure all containers. This script launch all `2*.sh` scripts
+ `containers/2*.sh` scripts is used to configure specific container, they are used by `11_install_next.sh` script

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

You can change change network settings of LXD containers in file `config/01_NETWORK_VARS`

## Editables variables

You can change this defaults variables in file `config/03_OTHER_VARS`

+ Default MAX upload file size (default: 5GB)
+ Default Language (default: French)
+ Time Zone (default: Europe/Paris)
+ Nextcloud Log rotate size (default: 100MB)
+ Nextcloud data directory (default: /srv/data-cloud)
+ LXD deported directory (default: /srv/lxd)
+ Debian Release (default: Stretch — 9)
+ Initialize lxd (default: true)
+ Create certificates (default: true)
+ LXD default storage driver (default: loop btrfs)

----------------------------------------

# Backups

## Data Backup

+ All Nextcloud data is defaultly stored in shared directory `/srv/data/cloud/`,
+ All configuration files (Nginx, Apache...) are stored in shared directory `/srv/lxd/`.

See [rsync backup](https://github.com/AlbanVidal/backup) example in my other repository

## Database (MariaDB) Backup

`/usr/local/bin/mysql-auto-dump` script are available in mariadb container.
He dump databases on shared directory `/srv/lxd/mariadb`
See below an example to use this with systemd timers

### Create Backup DB script

Please, edit `SRV`, `PORT` and `LOCAL_BACKUP_DIR` variables

```bash
cat << 'EOF' > /srv/backup-db.sh
#!/bin/bash

SRV='root@cloud.example.com'
PORT='22'
LOCAL_BACKUP_DIR='/srv/backup/data_bdd/'

# Delete OLD dump dans create new for copy
ssh -p $PORT $SRV 'bash -s' <<< '
    rm -f /srv/lxd/mariadb/mysqldump_*
    /snap/bin/lxc exec mariadb -- /usr/local/bin/mysql-auto-dump
'

# Copy in local
scp -P$PORT "$SRV":/srv/lxd/mariadb/mysqldump_*.tar.gz $LOCAL_BACKUP_DIR
EOF

# Set script as executable
chmod +x /srv/backup-db.sh
```

### Create Backup DB service (systemd)
```bash
cat << EOF > /etc/systemd/system/backup-db.service
[Unit]
Description=Backup databases script

[Service]
Type=oneshot
ExecStart=/srv/backup-db.sh
EOF
```

### Create Backup DB timer (systemd - cron like)
```bash
cat << EOF > /etc/systemd/system/backup-db.timer
[Unit]
Description=Backup databases Timer

[Timer]
# Time between running each consecutive time
OnCalendar=daily

[Install]
WantedBy=timers.target
EOF
```

### Reload daemon, enable and start the timer
```bash
systemctl daemon-reload
systemctl enable --now backup-db.timer
```

### You can check timer status, and timers
```bash
systemctl status backup.timer
systemctl list-timers
```

----------------------------------------

# Tips

## Screen

With `lxc shell` or `lxc exec <ct_name> bash`, you can't open **screen** in container

We have two solution for that :
  1. Use ssh
  2. Open tty: `lxc exec cloud -- bash -c "exec >/dev/tty 2>&1 </dev/tty && bash"`

----------------------------------------

# Bugs

**Debian 10 fails:**
+ mariadb with systemd (ownership in unprivileged container)
+ redis-server with systemd (ownership in unprivileged container)
