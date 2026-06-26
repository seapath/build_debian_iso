#!/bin/bash

wd=$(dirname "$0")
output_dir=.
COMPOSE_FILE="$(realpath "$wd"/podman-compose.yml)"

DISKSIZE="10G"
CLOUD_INIT=
if ! OPTIONS=$(getopt -o hvs:c --long help,version,vmdisksize:,cloud-init -- "$@"); then
    echo "Usage: $0 [-h|--help] [-v|--version] [-s|--vmdisksize SIZE] [-c|--cloud-init]" >&2
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
            echo "  -c, --cloud-init     Include cloud-init in the VM image (SEAPATH_CLOUD_INIT class)"
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
        -c|--cloud-init)
            CLOUD_INIT=true
            shift
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
CONTAINER_ENGINE=(sudo podman)
echo "We are going to use" "${CONTAINER_ENGINE[*]}" and "${COMPOSECMD[*]}"

rm -f $output_dir/seapath-vm.qcow2
# removing the volume in case it exists from a precedent build operation
"${CONTAINER_ENGINE[@]}" rm -f fai-setup 2>/dev/null
"${CONTAINER_ENGINE[@]}" volume rm seapath-debian-ext 2>/dev/null

set -ex

"${CONTAINER_ENGINE[@]}" build "$wd" --tag fai

rm -rf "$wd"/build_tmp/*
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

# Create the default config space
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup

# Adding the SEAPATH config
"${CONTAINER_ENGINE[@]}" cp "$wd"/build_tmp/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down

# ARM64 or AMD64
arch=$(uname -m)
if [ "$arch" == "aarch64" ]; then
    seapatharch="SEAPATH_ARM64"
else
    seapatharch="SEAPATH_AMD64"
fi

# Creating the VM
# patches /sbin/install_packages (bug in the process of being corrected upstream)
# patches GRUB_EFI/10-setup:
# - "efibootmgr -v" runs on the build host (not in the chroot) for LVM-backed
#   boot devices, but build hosts have no EFI firmware, so it fails with "EFI
#   variables are not supported on this system" and aborts the whole script.
#   It is only an informational dump of NVRAM boot entries, so we can safely
#   ignore its failure.
# - for LVM-backed boot devices, the script calls "grub-install $opts $GROOT"
#   without --force-extra-removable/--no-nvram (unlike its loop-device branch),
#   so the resulting image gets neither a usable NVRAM entry (the build host
#   has no EFI firmware to write one to, and none could be embedded in a
#   portable image anyway) nor a fallback bootloader at \EFI\BOOT\BOOTX64.EFI.
#   Fresh UEFI firmware then has nothing to boot and drops to the UEFI Shell.
#   Force the same flags as the loop-device branch so the image is bootable.
CLOUD_INIT_CLASS=
if [ "$CLOUD_INIT" = true ]; then
    CLOUD_INIT_CLASS="SEAPATH_CLOUD_INIT,"
fi
CLASSES="DEBIAN,FAIBASE,FRENCH,TRIXIE64,SEAPATH_COMMON,GRUB_EFI,SEAPATH_RAW,${seapatharch},SEAPATH_VM,${CLOUD_INIT_CLASS}USERCUSTOMIZATION,BUILD_QCOW2,LAST"
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  sed -i -e \"s/efibootmgr -v/efibootmgr -v || true/\" /ext/srv/fai/config/scripts/GRUB_EFI/10-setup && \
  sed -i -e \"s/grub-install \\\$opts \\\"\\\$GROOT\\\"/grub-install \\\$opts --force-extra-removable --no-nvram \\\"\\\$GROOT\\\"/\" /ext/srv/fai/config/scripts/GRUB_EFI/10-setup && \
  fai-diskimage -vu seapath-vm -S${DISKSIZE} -c$CLASSES -s /ext/srv/fai/config /ext/seapath-vm.qcow2"

# Retrieving the ISO from the volume
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup
echo "${CONTAINER_ENGINE[@]}" cp fai-setup:/ext/seapath-vm.qcow2 $output_dir/
"${CONTAINER_ENGINE[@]}" cp fai-setup:/ext/seapath-vm.qcow2 $output_dir/
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down --remove-orphans

# Removing the volume
"${CONTAINER_ENGINE[@]}" volume rm seapath-debian-ext
rm -rf "$wd"/build_tmp/*
