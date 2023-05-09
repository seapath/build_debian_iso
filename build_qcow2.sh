#!/bin/bash

wd=$(dirname $0)
output_dir=.

rm -f $output_dir/seapath.qcow2
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

# Create a NFSROOT
# This command also create a basefile which will be used by fai-diskimage
docker-compose -f $wd/docker-compose.yml run --rm fai-setup \
    fai-setup -v -e -f

# Starting the container to add stuff in it
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH workspace
docker cp $wd/srv_fai_config/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
docker-compose -f $wd/docker-compose.yml down

# Copy the basefile in fai configuration space
docker-compose -f $wd/docker-compose.yml run --rm fai-setup \
  cp /ext/nfsroot/var/tmp/base.tar.xz /ext/srv/fai/config/basefiles/SEAPATH_VM.tar.xz

# Creating the VM
cl="DEBIAN,FAIBASE,SEAPATH_COMMON,SEAPATH_VM,GRUB_EFI,LAST"
docker-compose -f $wd/docker-compose.yml run --rm fai-cd \
  fai-diskimage -vu seapath-vm -S10G -c$cl -s /ext/srv/fai/config /ext/seapath-vm.qcow2

# Retrieving the ISO from the volume
docker-compose -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath-vm.qcow2 $output_dir/
docker-compose -f $wd/docker-compose.yml down

# Removing the volume
docker volume rm build_debian_iso_ext
