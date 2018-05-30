#!/bin/bash

# Dump destination directory
DST_DIR="/srv/lxd"

################################################################################

# Dump 1:
# For each databases in localhost
for BDD in $(mysql -u root -Bse 'SHOW DATABASES;'|grep -v -E '(_schema|mysql)')
do
  # dump :
  mysqldump -u root $BDD > "${DST_DIR}/mysqldump_"$(date +%F)"_"$BDD".dump"
  # archive et compression du dump :
  tar cvaf "${DST_DIR}/mysqldump_"$(date +%F)"_"$BDD".dump.tar.gz" -C $DST_DIR "mysqldump_"$(date +%F)"_"$BDD".dump"
done

################################################################################

# Dump 2:
# Full dump
mysqldump -u root --all-databases > "${DST_DIR}/mysqldump_"$(date +%F)"_ALL.dump"
tar cvaf "${DST_DIR}/mysqldump_"$(date +%F)"_ALL.dump.tar.gz" -C ${DST_DIR} "mysqldump_"$(date +%F)"_ALL.dump"

################################################################################
