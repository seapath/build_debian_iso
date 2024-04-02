#!/bin/bash

wd=$(dirname $0)
output_dir=.

# test if "docker compose" works
docker compose >/dev/null 2>&1
returncode=$?
if [ $returncode -eq 0 ]; then
  COMPOSECMD="docker compose"
else
  COMPOSECMD="docker-compose"
fi
echo "We are going to use $COMPOSECMD"

rm -f $output_dir/seapath-vm.qcow2
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

# Create the default config space
$COMPOSECMD -f $wd/docker-compose.yml run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
$COMPOSECMD -f $wd/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH config
docker cp $wd/srv_fai_config/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
$COMPOSECMD -f $wd/docker-compose.yml down

# Creating the VM
# patches /sbin/install_packages (bug in the process of being corrected upstream)
CLASSES="DEBIAN,FAIBASE,FRENCH,BOOKWORM64,SEAPATH_COMMON,SEAPATH_VM,GRUB_EFI,LAST"
$COMPOSECMD -f $wd/docker-compose.yml run fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu seapath-vm -S10G -c$CLASSES -s /ext/srv/fai/config /ext/seapath-vm.qcow2"

# Retrieving the ISO from the volume
$COMPOSECMD -f $wd/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath-vm.qcow2 $output_dir/
$COMPOSECMD -f $wd/docker-compose.yml down --remove-orphans

# Removing the volume
docker volume rm build_debian_iso_ext
