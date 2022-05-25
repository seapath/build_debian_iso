#!/bin/bash

wd=`dirname $0`
#docker-compose -f $wd/docker-compose.yml run --rm fai-setup bash -c "rm -rf /ext/*"
docker volume rm  build_debian_iso_ext2>/dev/null
docker-compose -f $wd/docker-compose.yml run --rm fai-setup fai-setup -v -e
docker-compose -f $wd/docker-compose.yml run --rm fai-setup fai-mirror -c DEBIAN,SEAPATH_LVM,FAIBASE,DEMO,SEAPATH,SEAPATH_NOLVM,GRUB_EFI /ext/mirror
docker-compose -f $wd/docker-compose.yml run --rm fai-cd fai-cd -f -m /ext/mirror /ext/seapath.iso
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath.iso .
docker-compose -f $wd/docker-compose.yml down
docker volume rm build_debian_iso_ext 

