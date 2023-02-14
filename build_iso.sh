#!/bin/bash

wd=$(dirname $0)

rm $wd/seapath.iso
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

# Creating the NFSROOT
# Removing *.profile makes our seapath.profile the default
docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "fai-setup -v -e -f && rm -f /ext/srv/fai/config/class/*.profile"

# Starting the container to add stuff in it
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH workspace
docker cp $wd/srv_fai_config/. fai-setup:/ext/srv/fai/config/
# Adding the php:apache docker image
docker pull php:apache
mkdir -p /tmp/php_image/opt/php_apache.tgz
docker save php:apache | gzip > /tmp/php_image/opt/php_apache.tgz/SEAPATH
echo docker cp /tmp/php_image/. fai-setup:/ext/src/fai/files/
docker cp /tmp/php_image/. fai-setup:/ext/srv/fai/config/files/
rm -rf /tmp/php_image/

# Stopping the container after having added stuff in it
docker-compose -f $wd/docker-compose.yml down

# Creating the mirror
docker-compose -f $wd/docker-compose.yml run --rm fai-setup fai-mirror -c DEBIAN,SEAPATH_LVM,FAIBASE,DEMO,SEAPATH,SEAPATH_NOLVM,GRUB_EFI /ext/mirror

# Creating the ISO
docker-compose -f $wd/docker-compose.yml run --rm fai-cd fai-cd -f -m /ext/mirror /ext/seapath.iso

# Retrieving the ISO from the volume
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath.iso $wd/
docker-compose -f $wd/docker-compose.yml down

# Removing the volume
docker volume rm build_debian_iso_ext
