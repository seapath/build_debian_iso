#!/bin/bash

wd=$(dirname "$0")
output_dir=.

DISKSIZE="10G"
if ! OPTIONS=$(getopt -o hvs: --long help,version,vmdisksize: -- "$@"); then
    echo "Usage: $0 [-h|--help] [-v|--version] [-s|--vmdisksize SIZE]" >&2
    exit 1
fi
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -h, --help           Display this help message"
            echo "  -v, --version        Display version information"
            echo "  -s, --vmdisksize SIZE Specify the VM disk size (required argument)"
            exit 0
            ;;
        -v|--version)
            echo "Version 1.0"
            exit 0
            ;;
        -s|--vmdisksize)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                echo "VM disk size specified: $2"
                DISKSIZE=$2
                shift 2
            else
                echo "Error: The -s|--vmdisksize option requires an argument." >&2
                exit 1
            fi
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
if [ $# -gt 0 ]; then
    echo "Additional arguments: $*"
fi

COMPOSECMD=(sudo podman-compose)
echo "We are going to use" "${COMPOSECMD[@]}"

rm -f $output_dir/seapath-vm.qcow2
# removing the volume in case it exists from a precedent build operation
sudo podman rm -f fai-setup 2>/dev/null
sudo podman volume rm build_debian_iso_ext 2>/dev/null

set -ex

rm -rf "$wd"/build_tmp/*
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

# Create the default config space
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" up --no-start fai-setup

# Adding the SEAPATH config
sudo podman cp "$wd"/build_tmp/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" down

# ARM64 or AMD64
arch=$(uname -m)
if [ "$arch" == "aarch64" ]; then
    seapatharch="SEAPATH_ARM64"
else
    seapatharch="SEAPATH_AMD64"
fi

# Creating the VM
# patches /sbin/install_packages (bug in the process of being corrected upstream)
CLASSES="DEBIAN,FAIBASE,FRENCH,TRIXIE64,SEAPATH_COMMON,GRUB_EFI,SEAPATH_RAW,${seapatharch},SEAPATH_VM,USERCUSTOMIZATION,LAST"
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" run --rm fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu seapath-vm -S${DISKSIZE} -c$CLASSES -s /ext/srv/fai/config /ext/seapath-vm.qcow2"

# Retrieving the ISO from the volume
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" up --no-start fai-setup
sudo podman cp fai-setup:/ext/seapath-vm.qcow2 $output_dir/
"${COMPOSECMD[@]}" -f "$(realpath $wd/docker-compose.yml)" down --remove-orphans

# Removing the volume
sudo podman volume rm build_debian_iso_ext
rm -rf "$wd"/build_tmp/*
