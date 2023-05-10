#!/bin/bash

wd=$(dirname $0)
output_dir=.

rm -f $output_dir/seapath.iso
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

# Creating the NFSROOT
# Removing *.profile makes our seapath.profile the default
docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "\
    fai-setup -v -e -f && \
    rm -f /ext/srv/fai/config/class/*.profile"

# Starting the container to add stuff in it
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH workspace
docker cp $wd/srv_fai_config/. fai-setup:/ext/srv/fai/config/

# Stopping the container after having added stuff in it
docker-compose -f $wd/docker-compose.yml down

# Creating the mirror
CLASSES="DEBIAN,SEAPATH_LVM,FAIBASE,SEAPATH_COMMON,SEAPATH_HOST,SEAPATH_NOLVM,GRUB_EFI"
docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "\
    cp /etc/fai/apt/keys/* /etc/apt/trusted.gpg.d/ &&\
    fai-mirror -c $CLASSES /ext/mirror"

# Creating the ISO
docker-compose -f $wd/docker-compose.yml run --rm fai-cd fai-cd -f -m /ext/mirror /ext/seapath.iso

# Retrieving the ISO from the volume
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath.iso $output_dir/
docker-compose -f $wd/docker-compose.yml down

# Removing the volume
docker volume rm build_debian_iso_ext
