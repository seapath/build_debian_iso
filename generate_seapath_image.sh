#!/bin/bash

version="1.0"

print_usage() {
    echo 'This script generates SEAPATH images base on Debian to be used in the "seapath-installer".'
    echo ""
    echo "Usage: generate_seapath_image.sh role [options]"
    echo ""
    echo "Roles:"
    echo "  standalone             Generate a standalone hypervisor image"
    echo "  cluster                Generate a hypervisor image for cluster deployment"
    echo "  observer               Generate a cluster observer node image"
    echo ""
    echo "Options:"
    echo "  -h, --help             Display this help message"
    echo "  -v, --version          Display version information"
    echo "  -s, --disk-size        SIZE Specify the disk size (default is 60G)"
    echo "  -c, --enable-cockpit   Enable Cockpit installation"
    echo "  -d, --enable-debug     Generate a debug image with additional tools"
    echo "  -n, --name NAME        Specify the output image name without extension (default is seapath)"
    echo "  -o, --output-dir DIR   Specify the output directory (default is current directory)"
    echo "  -a, --arch ARCH        Specify the architecture (AMD64 or ARM64). Default is AMD64"
    echo "  -x, --verbose          Enable debug mode for the script"
    echo "      --docker           Force using 'docker' instead of 'podman' (if both are installed)"
    echo "      --ceph-disk        Include Ceph dedicated disk configuration"
    echo "      --hostname NAME    Specify the hostname (default is seapath)"
}

if [ $# -lt 1 ]; then
    echo "Error: No role specified." >&2
    echo
    print_usage
    exit 1
fi

if [ "${1,,}" == "-h" ] || [ "${1,,}" == "--help" ]; then
    print_usage
    exit 0
fi

wd=$(dirname "$0")
output_dir=.
OUTPUT=seapath.raw
ROLE="$1"
HOSTNAME=seapath
COCKPIT=
FORCE_DOCKER=
DISKSIZE="60G"
if [ "$ROLE" != "cluster" ]; then
    CEPH_DISK=",SEAPATH_CEPH_DISK"
else
    CEPH_DISK=
fi
ARCH="SEAPATH_AMD64"
HYPERVISOR=
CLUSTER=
DEBUG=
if [ "$ROLE" == "standalone" ] || [ "$ROLE" == "cluster" ]; then
    HYPERVISOR=",SEAPATH_HOST"
fi
if [ "$ROLE" == "cluster" ] || [ "$ROLE" == "observer" ]; then
    CLUSTER=",SEAPATH_CLUSTER"
fi
shift

if ! OPTIONS=$(getopt -o hvs:cn:o:a:xd --long help,version,disk-size:,enable-cockpit,name:,output-dir:,ceph-disk,arch:,hostname:,verbose,docker -- "$@"); then
    print_usage
    exit 1
fi
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -v|--version)
            echo "Version $version"
            exit 0
            ;;
        -s|--disk-size)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                echo "Disk size specified: $2"
                DISKSIZE=$2
                shift 2
            else
                echo "Error: The -s|--disk-size option requires an argument." >&2
                exit 1
            fi
            ;;
        -a|--arch)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                if [[ "${2,,}" == "amd64" ]]; then
                    ARCH="SEAPATH_AMD64"
                elif [[ "${2,,}" == "arm64" ]]; then
                    ARCH="SEAPATH_ARM64"
                else
                    echo "Error: The -a|--arch option requires either AMD64 or ARM64 as argument." >&2
                    exit 1
                fi
                shift 2
            else
                echo "Error: The -a|--arch option requires an argument." >&2
                exit 1
            fi
            ;;
        -c|--enable-cockpit)
            COCKPIT=",SEAPATH_COCKPIT"
            shift
            ;;
        -d|--enable-debug)
            DEBUG=",SEAPATH_DBG"
            shift
            ;;
        -n|--name)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                OUTPUT="$2.raw"
                HOSTNAME="$2"
                shift 2
            else
                echo "Error: The -n|--name option requires an argument." >&2
                exit 1
            fi
            ;;
        -o|--output-dir)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                output_dir="$(pwd)/$2"
                shift 2
            else
                echo "Error: The -o|--output-dir option requires an argument." >&2
                exit 1
            fi
            ;;
        --ceph-disk)
            if [ "$ROLE" == "cluster" ]; then
                CEPH_DISK=",SEAPATH_CEPH_DISK"
            else
                echo "Warning: --ceph-disk option is only applicable for 'cluster' role. Ignoring." >&2
            fi
            shift
            ;;
        --hostname)
            if [ -n "$2" ] && [[ $2 != -* ]]; then
                HOSTNAME="$2"
                shift 2
            else
                echo "Error: The --hostname option requires an argument." >&2
                exit 1
            fi
            ;;
        --docker)
            FORCE_DOCKER=1
            shift
            ;;
        -x|--verbose)
            set -x
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo
            print_usage
            exit 1
            ;;
    esac
done

if [[ "$ROLE" != "standalone" && "$ROLE" != "cluster" && "$ROLE" != "observer" ]]; then
    echo "Error: Invalid role specified: $ROLE" >&2
    exit 1
fi


COMPOSECMD="sudo podman-compose"
CONTAINER_ENGINE="sudo podman"

if [ -z "$FORCE_DOCKER" ]; then
    # test if podman-compose works
    podman-compose version >/dev/null 2>&1
    returncode=$?
    if [ $returncode -ne 0 ]; then
        FORCE_DOCKER=1
    fi
fi

if [ -n "$FORCE_DOCKER" ]; then

    CONTAINER_ENGINE="docker"
    # test if "docker compose" works
    docker compose >/dev/null 2>&1
    returncode=$?
    if [ $returncode -eq 0 ]; then
    COMPOSECMD="docker compose"
    else
    if ! command -v docker-compose >/dev/null 2>&1; then
        echo "Error: Neither 'podman-compose' nor 'docker compose' nor 'docker-compose' command is available. Please install one of them." >&2
        exit 1
    fi
    COMPOSECMD="docker-compose"
    fi
fi

#cd "$wd" || exit 1

echo "We are going to use $COMPOSECMD"

mkdir -p "$output_dir"

rm -f "$output_dir/${OUTPUT} $output_dir/${OUTPUT}.bmap $output_dir/${OUTPUT}.gz"
# removing the volume in case it exists from a precedent build operation
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" down --volumes 2>/dev/null

set -e

rm -rf "$wd"/build_tmp/*
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

$COMPOSECMD build

# Create the default config space
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" up --no-start fai-setup

echo mkdir -p "$wd"/build_tmp/files/usr/local/bin/cephadm
mkdir -p "$wd"/build_tmp/files/usr/local/bin/cephadm
echo wget -O "$wd"/build_tmp/files/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm
wget -O "$wd"/build_tmp/files/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm

# Adding the SEAPATH config
$CONTAINER_ENGINE cp "$wd"/build_tmp/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" down fai-setup

# Creating the disk
# patches /sbin/install_packages (bug in the process of being corrected upstream)
CLASSES="FAIBASE,DEBIAN,GRUB_EFI,SEAPATH_COMMON,${HYPERVISOR}${CLUSTER}${COCKPIT}${DEBUG},${ARCH},SEAPATH_RAW${CEPH_DISK},USERCUSTOMIZATION,LAST"
echo "Generate with FAI classes: $CLASSES"
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" run --rm fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu ${HOSTNAME} -S${DISKSIZE} -c$CLASSES -s /ext/srv/fai/config /ext/${OUTPUT}"

# Retrieving the ISO from the volume
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" up --no-start fai-setup
OUTPUT_PATH=$($CONTAINER_ENGINE volume inspect --format '{{ .Mountpoint }}' build_debian_iso_ext)/${OUTPUT}
sudo mv "$OUTPUT_PATH" "$output_dir/${OUTPUT}"
sudo chown "$(id -u):$(id -g)" "$output_dir/${OUTPUT}"

# Ensure all is stopped and cleaned (this command may fail if some containers are not running)
set +e
$COMPOSECMD -f "$(realpath $wd/docker-compose.yml)" down --remove-orphans --volumes 2>/dev/null
set -e

rm -rf "$wd"/build_tmp/*

if command -v bmaptool >/dev/null ; then

    bmaptool create -o "$output_dir/${OUTPUT}.bmap" "$output_dir/${OUTPUT}"

    if command -v pigz >/dev/null ; then
        pigz "$output_dir/${OUTPUT}"
    else
        gzip "$output_dir/${OUTPUT}"
    fi
fi

echo "SEAPATH image generation completed."
