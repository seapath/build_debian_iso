#!/bin/bash

wd=`dirname $0`
#docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "rm -rf /ext/*"

# removing the volume in case it exists from a precedent build operation
docker volume rm  build_debian_iso_ext 2>/dev/null

# creating the NFSROOT
docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "fai-setup -v -e; rm -f /ext/srv/fai/config/class/*.profile"

# Addding the SEAPATH workspace
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp $wd/srv_fai_config/. fai-setup:/ext/srv/fai/config/
docker-compose -f $wd/docker-compose.yml down

# Creating the mirror
docker-compose -f $wd/docker-compose.yml run --rm fai-setup fai-mirror -c DEBIAN,SEAPATH_LVM,FAIBASE,DEMO,SEAPATH,SEAPATH_NOLVM,GRUB_EFI /ext/mirror

# Creating the ISO
docker-compose -f $wd/docker-compose.yml run --rm fai-cd fai-cd -f -m /ext/mirror /ext/seapath.iso

# Retrieving the ISO from the volume
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath.iso .
docker-compose -f $wd/docker-compose.yml down

# Removing the volume
docker volume rm build_debian_iso_ext 

