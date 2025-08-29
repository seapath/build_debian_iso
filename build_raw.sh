#!/bin/bash

wd=$(dirname "$0")
output_dir=.

OUTPUT=seapath.raw
HOSTNAME=seapath

DISKSIZE="60G"
if ! OPTIONS=$(getopt -o hvs: --long help,version,rawdisksize: -- "$@"); then
    echo "Usage: $0 [-h|--help] [-v|--version] [-s|--rawdisksize SIZE]" >&2
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
            echo "  -s, --rawdisksize SIZE Specify the RAW disk size (required argument)"
            exit 0
            ;;
        -v|--version)
            echo "Version 1.0"
            exit 0
            ;;
        -s|--rawdisksize)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                echo "RAW disk size specified: $2"
                DISKSIZE=$2
                shift 2
            else
                echo "Error: The -s|--rawdisksize option requires an argument." >&2
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

# test if "docker compose" works
docker compose >/dev/null 2>&1
returncode=$?
if [ $returncode -eq 0 ]; then
  COMPOSECMD="docker compose"
else
  COMPOSECMD="docker-compose"
fi
echo "We are going to use $COMPOSECMD"

rm -f "$output_dir/${OUTPUT} $output_dir/${OUTPUT}.bmap $output_dir/${OUTPUT}.gz"
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

rm -rf "$wd"/build_tmp/*
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

# Create the default config space
$COMPOSECMD -f "$wd"/docker-compose.yml run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
$COMPOSECMD -f "$wd"/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH config
docker cp "$wd"/build_tmp/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
$COMPOSECMD -f "$wd"/docker-compose.yml down

# ARM64 or AMD64
arch=$(uname -m)
if [ "$arch" == "aarch64" ]; then
    seapatharch="SEAPATH_ARM64"
else
    seapatharch="SEAPATH_AMD64"
fi

# Creating the disk
# patches /sbin/install_packages (bug in the process of being corrected upstream)
CLASSES="FAIBASE,DEBIAN,GRUB_EFI,SEAPATH_COMMON,SEAPATH_HOST,SEAPATH_CLUSTER,SEAPATH_COCKPIT,USERCUSTOMIZATION,SEAPATH_AMD64,LAST"
echo $CLASSES
$COMPOSECMD -f "$wd"/docker-compose.yml run --rm fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu ${HOSTNAME} -S${DISKSIZE} -c$CLASSES -s /ext/srv/fai/config /ext/${OUTPUT}"

# Retrieving the ISO from the volume
$COMPOSECMD -f "$wd"/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/${OUTPUT} $output_dir/
$COMPOSECMD -f "$wd"/docker-compose.yml down --remove-orphans

# Removing the volume
docker volume rm build_debian_iso_ext

if command -v bmaptool >/dev/null ; then

    bmaptool create -o "$output_dir/${OUTPUT}.bmap" "$output_dir/${OUTPUT}"

    if command -v pigz >/dev/null ; then
        pigz "$output_dir/${OUTPUT}"
    else
        gzip "$output_dir/${OUTPUT}"
    fi
fi


rm -rf "$wd"/build_tmp/*
