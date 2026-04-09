#!/bin/bash

version="2.1"

set -e

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
output_dir=.
ext_dir=$wd/ext
fai_config_dir=$ext_dir/srv/fai/config
OUTPUT=seapath.raw

ROLE="$1"
shift
HOSTNAME=seapath
COCKPIT=
DEBUG=
DISKSIZE="60G"
ARCH="SEAPATH_AMD64"
if [ "$ROLE" != "cluster" ]; then
    CEPH_DISK=true
else
    CEPH_DISK=false
fi

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
            COCKPIT=true
            shift
            ;;
        -d|--enable-debug)
            DEBUG=true
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
                CEPH_DISK=true
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

IFS=','
CLASSES=(FAIBASE DEBIAN GRUB_EFI SEAPATH_COMMON)
if [ "$ROLE" == "standalone" ] || [ "$ROLE" == "cluster" ]; then
    CLASSES+=("SEAPATH_HOST")
fi
if [ "$ROLE" == "cluster" ] || [ "$ROLE" == "observer" ]; then
    CLASSES+=("SEAPATH_CLUSTER")
fi
if [ "$COCKPIT" = true ]; then
    CLASSES+=("SEAPATH_COCKPIT")
fi
if [ "$DEBUG" = true ]; then
    CLASSES+=("SEAPATH_DBG")
fi
CLASSES+=("$ARCH" SEAPATH_RAW)
if [ "$CEPH_DISK" = true ]; then
    CLASSES+=("SEAPATH_CEPH_DISK")
fi
CLASSES+=(USERCUSTOMIZATION LAST)

echo "Generate with FAI classes: ${CLASSES[*]}"

function has_class {
    class_name=$1
    [[ "${IFS}${CLASSES[*]}${IFS}" =~ ${IFS}${class_name}${IFS} ]]
    return $?
}

CONTAINER_ENGINE=(sudo podman)
echo "We are going to use" "${CONTAINER_ENGINE[*]}"

CONTAINER_IMAGE_NAME=fai

"${CONTAINER_ENGINE[@]}" build . --tag "$CONTAINER_IMAGE_NAME"

function docker_run {
    "${CONTAINER_ENGINE[@]}" run \
        --rm \
        --privileged \
        -v ./ext:/ext:Z \
        -v ./etc_fai:/etc/fai:ro,Z \
        -v /dev:/dev \
        -v /tmp/fai:/var/log/fai:Z \
        "$CONTAINER_IMAGE_NAME" "$@"
}

# Removing the old generated artifacts
rm -f "$output_dir/${OUTPUT}"{,.bmap,.gz}
rm -rf "$output_dir/sbom"

# Removing the build directory in case it exists from a precedent build operation.
sudo rm -rf "$ext_dir"

mkdir -p "$output_dir" "$ext_dir" "/tmp/fai"

# Create the default config space
docker_run fai-mk-configspace

sudo mkdir "$ext_dir/output"
sudo cp -r "$wd/srv_fai_config/"* "$fai_config_dir"
sudo cp -r "$wd/usercustomization/"* "$fai_config_dir"

sudo mkdir -p "$fai_config_dir/files/usr/local/bin/cephadm"
sudo wget -O "$fai_config_dir/files/usr/local/bin/cephadm/SEAPATH_CLUSTER" https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm

# Adding the container images
# Process container_images.conf files for all classes that have them
# This handles images for SEAPATH_CLUSTER, SEAPATH_HOST, USERCUSTOMIZATION, and any other classes
CONTAINER_IMAGES_CONFIG_DIR="$fai_config_dir/files/etc/container_images.conf"

if [ -d "$CONTAINER_IMAGES_CONFIG_DIR" ]; then
    image_dir="$fai_config_dir/files/opt/images"
    sudo mkdir -p "$image_dir"
    # Process each class configuration file
    for class_conf_file in "$CONTAINER_IMAGES_CONFIG_DIR"/*; do
        [ -f "$class_conf_file" ] || continue

        class_name=$(basename "$class_conf_file")

        if ! has_class "$class_name"; then
            echo "Skipped download of images for class $class_name"
            continue
        fi
        echo "Processing container images for class $class_name"

        # Read images from config file (ignore comments and empty lines)
        while IFS= read -r i || [ -n "$i" ]; do
            # Skip empty lines and comments
            [[ -z "$i" || "$i" =~ ^[[:space:]]*# ]] && continue
            # Trim whitespace
            i=$(echo "$i" | xargs)
            [[ -z "$i" ]] && continue

            registry=$(echo "$i" | cut -d'/' -f2)
            image=$(echo "$i" | cut -d'/' -f3 | sed s/://g)
            image_file="$image_dir/${registry}_${image}"

            echo "Downloading image: $i"
            "${CONTAINER_ENGINE[@]}" pull "$i"
            echo "Saving image $i to $image_file"
            "${CONTAINER_ENGINE[@]}" save "$i" --format oci-archive --output "$image_file"
        done < "$class_conf_file"
    done
else
    echo "Warning: container_images.conf directory not found, skipping image import" >&2
fi

# Creating the disk
# patches /sbin/install_packages (bug in the process of being corrected upstream)
docker_run bash -c "\
  sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /sbin/install_packages && \
  sed -i -e \"s/ --allow-change-held-packages//\" /sbin/install_packages && \
  sed -i -e \"s/-c -o compression_type=zstd qcow2/qcow2/\" /usr/sbin/fai-diskimage && \
  fai-diskimage -vu ${HOSTNAME} -S${DISKSIZE} -c${CLASSES[*]} -s /ext/srv/fai/config /ext/output/${OUTPUT}"

# Retrieving the output files from the volume (image and SBOM)
sudo mv "$ext_dir/output/"* "$output_dir/"
sudo chown -R "$(id -u):$(id -g)" "$output_dir/"*

# Clean the build directory
sudo rm -rf "$ext_dir"

if command -v bmaptool >/dev/null ; then

    bmaptool create -o "$output_dir/${OUTPUT}.bmap" "$output_dir/${OUTPUT}"

    if command -v pigz >/dev/null ; then
        pigz "$output_dir/${OUTPUT}"
    else
        gzip "$output_dir/${OUTPUT}"
    fi
fi

echo "SEAPATH image generation completed."
