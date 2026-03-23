#!/bin/bash

version="2.0"

function generate_seapath_metadata() {
    OUTPUT=$OUTPUT output_dir=$output_dir role=$ROLE python3 - << END
from pathlib import Path
import xml.etree.ElementTree as ET
import hashlib
from os import environ

working_dir = environ.get('output_dir', '')
bmap_file = f'{environ.get('OUTPUT', '')}.bmap'

role = environ.get('role', '')
role = role.lower()

if 'standalone' in role:
    setup = 'Standalone'
else:
    setup = 'Cluster'

# image_deploy_dir = Path(d.getVar('IMGDEPLOYDIR'))
# bmap_image_name = d.getVar('IMAGE_LINK_NAME')
bmap_path = working_dir + f'/{bmap_file}'
print(bmap_path)
# if not bmap_path.exists():
#    raise 'Missing bmap file: %s' % bmap_path

bmap_tree = ET.parse(str(bmap_path))
root = bmap_tree.getroot()

for tag, value in [
    ('ImageName',        'SEAPATH Debian'),
    ('ImageVersion',     '1.2.0'),
    ('ImageDescription', 'A production image for SEAPATH'),
    ('ImageSetup', setup),
    ('ImageFlavor', 'Debian'),
]:
    node = ET.SubElement(root, tag)
    node.text = f' {value} '
    node.tail = '\n'


# bmap-tools check for bmap file interity with a checksum computed
# image build. As we modify the file we need to update the checksum
# of the file:
#   1. Reset the checksum to 0
#   2. Compute the checksum of the file
#   3. Replace with the new computed checksum
bmap_file_checksum = root.find('BmapFileChecksum')
len_bmap_file_checksum = len(str.strip(bmap_file_checksum.text))

bmap_file_checksum.text = '0' * len_bmap_file_checksum
root.tail = '\n'

bmap_tree.write(str(bmap_path), encoding='utf-8', xml_declaration=False)

checksum_type=root.find('ChecksumType')
checksum_type_value = str.strip(checksum_type.text)

block_size=root.find('BlockSize')
block_size_value = int(str.strip(block_size.text))
hash_obj = hashlib.new(str.strip(checksum_type.text))

with open(bmap_path, 'rb') as file:
    while chunk := file.read(block_size_value):
        hash_obj.update(chunk)

bmap_file_updated_hash = hash_obj.hexdigest()
bmap_file_checksum.text = bmap_file_updated_hash

bmap_tree.write(str(bmap_path), encoding='utf-8', xml_declaration=False)

END

}

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
SEAPATH_VERSION="1.2.0"
output_dir=.
OUTPUT=seapath.raw
ROLE="$1"
HOSTNAME=seapath
COCKPIT=
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

if ! OPTIONS=$(getopt -o hvs:cn:o:a:xd --long help,version,disk-size:,enable-cockpit,name:,output-dir:,ceph-disk,arch:,hostname:,verbose -- "$@"); then
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

COMPOSECMD=(sudo podman-compose)
CONTAINER_ENGINE=(sudo podman)
COMPOSE_FILE="$(realpath "$wd"/podman-compose.yml)"
echo "We are going to use" "${CONTAINER_ENGINE[*]}" and "${COMPOSECMD[*]}"

mkdir -p "$output_dir"

rm -f "$output_dir/${OUTPUT} $output_dir/${OUTPUT}.bmap $output_dir/${OUTPUT}.gz"
# removing the volume in case it exists from a precedent build operation
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down --volumes 2>/dev/null

set -e

rm -rf "$wd"/build_tmp/*
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

"${COMPOSECMD[@]}" build

# Create the default config space
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-setup \
    fai-mk-configspace

# Starting the container to add seapath stuff in the config space
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup

echo mkdir -p "$wd"/build_tmp/files/usr/local/bin/cephadm
mkdir -p "$wd"/build_tmp/files/usr/local/bin/cephadm
echo wget -O "$wd"/build_tmp/files/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm
wget -O "$wd"/build_tmp/files/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm

# Adding the SEAPATH config
"${CONTAINER_ENGINE[@]}" cp "$wd"/build_tmp/. fai-setup:ext/srv/fai/config/

# Stopping the container after having added stuff in it
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down fai-setup

# Creating the disk
# patches /sbin/install_packages (bug in the process of being corrected upstream)
CLASSES="FAIBASE,DEBIAN,GRUB_EFI,SEAPATH_COMMON,${HYPERVISOR}${CLUSTER}${COCKPIT}${DEBUG},${ARCH},SEAPATH_RAW${CEPH_DISK},USERCUSTOMIZATION,LAST"
echo "Generate with FAI classes: $CLASSES"
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-cd bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu ${HOSTNAME} -S${DISKSIZE} -c$CLASSES -s /ext/srv/fai/config /ext/${OUTPUT}"

# Retrieving the ISO from the volume
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup
OUTPUT_PATH=$("${CONTAINER_ENGINE[@]}" volume inspect --format '{{ .Mountpoint }}' build_debian_iso_ext)/${OUTPUT}
sudo mv "$OUTPUT_PATH" "$output_dir/${OUTPUT}"
sudo chown "$(id -u):$(id -g)" "$output_dir/${OUTPUT}"

# Ensure all is stopped and cleaned (this command may fail if some containers are not running)
set +e
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down --remove-orphans --volumes 2>/dev/null
set -e

rm -rf "$wd"/build_tmp/*

if command -v bmaptool >/dev/null ; then

    bmaptool create -o "$output_dir/${OUTPUT}.bmap" "$output_dir/${OUTPUT}"

    if command -v pigz >/dev/null ; then
        pigz "$output_dir/${OUTPUT}"
    else
        gzip "$output_dir/${OUTPUT}"
    fi
    generate_seapath_metadata
fi

echo "SEAPATH image generation completed."
