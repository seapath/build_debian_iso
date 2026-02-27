#!/bin/bash

wd=$(dirname "$0")
output_dir=.

COMPOSECMD=(sudo podman-compose)
CONTAINER_ENGINE=(sudo podman)
COMPOSE_FILE="$(realpath "$wd"/podman-compose.yml)"
echo "We are going to use" "${CONTAINER_ENGINE[*]}" and "${COMPOSECMD[*]}"

rm -f $output_dir/seapath.iso
# removing the volume in case it exists from a precedent build operation
"${CONTAINER_ENGINE[@]}" rm -f fai-setup 2>/dev/null
"${CONTAINER_ENGINE[@]}" volume rm build_debian_iso_ext 2>/dev/null

set -e

if [ ! -f "$wd"/etc_fai/grub.cfg ]; then
  cp "$wd"/etc_fai/grub_base.cfg "$wd"/etc_fai/grub.cfg
fi

find "$wd"/build_tmp/ ! -name .gitkeep -type f -exec rm -f {} +
cp -r "$wd/srv_fai_config/"* "$wd/build_tmp"
cp -r "$wd/usercustomization/"* "$wd/build_tmp"

finalClasses="SEAPATH_CLUSTER,SEAPATH_DBG,SEAPATH_KERBEROS,SEAPATH_COCKPIT,"

# Parse command line arguments
CUSTOM_MODE=false
CLASSES_ARG=""
MENU_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --custom)
      CUSTOM_MODE=true
      shift
      ;;
    --classes)
      if [ -z "$2" ] || [[ "$2" == --* ]]; then
        echo "Error: --classes requires a value" >&2
        exit 1
      fi
      CLASSES_ARG="$2"
      CUSTOM_MODE=true
      shift 2
      ;;
    --menu)
      if [ -z "$2" ] || [[ "$2" == --* ]]; then
        echo "Error: --menu requires a value" >&2
        exit 1
      fi
      MENU_ARG="$2"
      CUSTOM_MODE=true
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$CUSTOM_MODE" == true ]; then

  cp "$wd"/etc_fai/grub_base.cfg "$wd"/etc_fai/grub.cfg
  
  # Helper functions for TUI
  # add index to an array, for each value
  function addIndexToArray1 {
    local -n myarray=$1
    for idx in $(seq 1 ${#myarray[@]}); do
      arrVar+=("$idx"")")
      arrVar+=("${myarray[$((idx-1))]}")
    done
  }
  # add index to an array, every 2 values
  function addIndexToArray2 {
    local -n myarray=$1
    for idx in $(seq 1 $((${#myarray[@]}/2))); do
      arrVar+=("$idx"")")
      arrVar+=("${myarray[$((idx*2-2))]}")
      arrVar+=("${myarray[$((idx*2-1))]}")
    done
  }
  
  # If --classes is provided, use it directly, otherwise use TUI
  if [ -n "$CLASSES_ARG" ]; then
    # Add comma at the end if not present
    if [[ "$CLASSES_ARG" != *"," ]]; then
      finalClasses="$CLASSES_ARG,"
    else
      finalClasses="$CLASSES_ARG"
    fi
  else
    # Use TUI for classes selection

  listClasses=("SEAPATH_CLUSTER" "ON" "SEAPATH_DBG" "ON" "SEAPATH_COCKPIT" "ON" "SEAPATH_KERBEROS" "ON")
  arrVar=()
  addIndexToArray2 listClasses

    CHOICES=$(whiptail --separate-output --checklist "Choose package classes to add to iso" 18 60 7 \
    "${arrVar[@]}" 3>&1 1>&2 2>&3)
    finalClasses=""
    for CHOICE in $CHOICES; do
      c=${CHOICE//)/}
      c=$(((c-1)*2))
      finalClasses="$finalClasses""${listClasses[$c]}"","
    done
  fi
  
  # If --menu is provided, parse it directly, otherwise use TUI
  if [ -n "$MENU_ARG" ]; then
    # Split menu items by semicolon
    IFS=';' read -ra MENU_ITEMS <<< "$MENU_ARG"
    menuItems=()
    for item in "${MENU_ITEMS[@]}"; do
      # Trim whitespace
      item=$(echo "$item" | xargs)
      if [ -n "$item" ]; then
        menuItems+=("$item")
      fi
    done
    
    # If we have menu items, generate the grub config
    if [ ${#menuItems[@]} -gt 0 ]; then
      # First item is the default
      defaultMenuItem="${menuItems[0]}"
      
      echo "set default=\"  SEAPATH installation - $defaultMenuItem\""  > /tmp/seapathlistfai.txt
      echo "set timeout=5" >> /tmp/seapathlistfai.txt
      for menuItem in "${menuItems[@]}"; do
        entry="menuentry \"  SEAPATH installation - $menuItem\" {
        search --set=root --file /FAI-CD
        linux   /boot/vmlinuz FAI_FLAGS=\"$menuItem,verbose,sshd,createvt,reboot\" FAI_ACTION=install FAI_CONFIG_SRC=file:///var/lib/fai/config rd.live.image root=live:CDLABEL=FAI_CD ipv6.disable=1
        initrd  /boot/initrd.img
    }"
        echo "$entry" >> /tmp/seapathlistfai.txt
      done
      
      sed -i -ne '/## BEGIN CUSTOM MENU ITEMS/ {p; r /tmp/seapathlistfai.txt' -e ':a; n; /## END CUSTOM MENU ITEMS/ {p; b}; ba}; p' "$wd"/etc_fai/grub.cfg
      rm -f /tmp/seapathlistfai.txt
    fi
  else
    # Use TUI for menu selection
    addFlagCombination() {
      listFlags=("french" "FRENCH keyboard rather than english" "OFF" "german" "GERMAN keyboard rather than english" "OFF" "dbg" "DEBUG packages" "OFF" "raid" "lvm RAID" "OFF" "ceph_disk" "Ceph dedicated disk" "OFF" "cockpit" "COCKPIT packages" "OFF" "kerberos" "KERBEROS packages" "OFF" "cluster" "CLUSTER rather than standalone" "ON")
      arrVar=()
      if CHOICES=$(whiptail --separate-output --checklist "Choose flags combination to add to grub" 18 60 7 "${listFlags[@]}" 3>&1 1>&2 2>&3); then
        # code 0
        finalFlags=""
        if [ -z "$CHOICES" ]; then
          finalFlags="noflag"
        else
          for CHOICE in $CHOICES; do
            finalFlags="$finalFlags""${CHOICE}"","
          done
          finalFlags=${finalFlags::-1}
        fi
        menuItems+=("$finalFlags")
      fi
    }

    menuItems=()

    while true
    do
      menuItemsStr=""
      for menuItem in "${menuItems[@]}"; do
        menuItemsStr="$menuItemsStr\n""$menuItem"
      done
      whiptail --msgbox "this is the list of grub menu entries:\n$menuItemsStr\n" 20 100
      CHOICE=$(
      whiptail --title "grub menu" --cancel-button "exit" --menu "Make your choice:" 22 100 14 \
        "1)" "add grub entry (flag combinaison)"   \
        "2)" "continue"   \
        3>&2 2>&1 1>&3
      )
      [[ "$?" = 1 ]] && break

      case $CHOICE in
        "1)") addFlagCombination
        ;;
        "2)") break
        ;;
      esac
    done

    if [ ${#menuItems[@]} -gt 0 ]; then
    # if user has defined grub items, make him choose a default one
      CHOICE=$(
      addIndexToArray1 menuItems
      whiptail --title "choose default grub item" --cancel-button "exit" --menu "choose default grub entry:" 22 100 14 \
        "${arrVar[@]}" \
        3>&2 2>&1 1>&3
      )
      [[ "$?" = 1 ]] && exit
      c=${CHOICE//)/}

      echo "set default=\"  SEAPATH installation - ${menuItems[$((c-1))]}\""  > /tmp/seapathlistfai.txt
      echo "set timeout=5" >> /tmp/seapathlistfai.txt
      for menuItem in "${menuItems[@]}"; do
        entry="menuentry \"  SEAPATH installation - $menuItem\" {
        search --set=root --file /FAI-CD
        linux   /boot/vmlinuz FAI_FLAGS=\"$menuItem,verbose,sshd,createvt,reboot\" FAI_ACTION=install FAI_CONFIG_SRC=file:///var/lib/fai/config rd.live.image root=live:CDLABEL=FAI_CD ipv6.disable=1
        initrd  /boot/initrd.img
    }"
        echo "$entry" >> /tmp/seapathlistfai.txt
      done

      sed -i -ne '/## BEGIN CUSTOM MENU ITEMS/ {p; r /tmp/seapathlistfai.txt' -e ':a; n; /## END CUSTOM MENU ITEMS/ {p; b}; ba}; p' "$wd"/etc_fai/grub.cfg
      rm -f /tmp/seapathlistfai.txt
    fi
  fi

fi

# ARM64 or AMD64
arch=$(uname -m)
if [ "$arch" == "aarch64" ]; then
    bfile="BOOKWORM_ARM64.tar.xz"
else
    bfile="TRIXIE64.tar.xz"
fi

# Creating the NFSROOT
# Removing *.profile since we don't use them
# Removing 50-host-classes to prevent DEMO and FAIBASE to be added to the list of classes
# Adding the Bookworm basefiles to that we deploy a Debian v12 distro
# Patches /sbin/install_packages (bug in the process of being corrected upstream)
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-setup bash -c "\
    echo \"fai-setup -v -e -f \" && \
    fai-setup -v -e -f && \
    echo \"rm -f /ext/srv/fai/config/class/50-host-classes\" && \
    rm -f /ext/srv/fai/config/class/50-host-classes && \
    echo \"rm -f /ext/srv/fai/config/class/*.profile\" && \
    rm -f /ext/srv/fai/config/class/*.profile && \
    echo \"patch /usr/sbin/fai-cd /etc/fai/fai-cd.patch -o /ext/fai-cd\" && \
    patch /usr/sbin/fai-cd /etc/fai/fai-cd.patch -o /ext/fai-cd && chmod 755 /ext/fai-cd && \
    echo \"SED\" && \
    sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /ext/nfsroot/sbin/install_packages && \
    sed -i -e \"s/ --allow-change-held-packages//\" /ext/nfsroot/sbin/install_packages && \
    echo \"wget -O /ext/srv/fai/config/basefiles/${bfile} https://fai-project.org/download/basefiles/${bfile}\" && \
    wget -O /ext/srv/fai/config/basefiles/${bfile} https://fai-project.org/download/basefiles/${bfile}"

# Starting the container to add stuff in it
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup

# Adding the SEAPATH workspace
"${CONTAINER_ENGINE[@]}" cp "$wd"/build_tmp/. fai-setup:/ext/srv/fai/config/

# Adding the cephadm binary
echo mkdir -p /tmp/cephadm/usr/local/bin/cephadm
mkdir -p /tmp/cephadm/usr/local/bin/cephadm
echo wget -O /tmp/cephadm/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm
wget -O /tmp/cephadm/usr/local/bin/cephadm/SEAPATH_CLUSTER https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm
echo "${CONTAINER_ENGINE[@]}" cp /tmp/cephadm/. fai-setup:/ext/srv/fai/config/files/
"${CONTAINER_ENGINE[@]}" cp /tmp/cephadm/. fai-setup:/ext/srv/fai/config/files/
# Adding the container images
# Process container_images.conf files for all classes that have them
# This handles images for SEAPATH_CLUSTER, SEAPATH_HOST, USERCUSTOMIZATION, and any other classes
CONTAINER_IMAGES_BASE_DIR="$wd/build_tmp/files/etc/container_images.conf"
[ -d "$CONTAINER_IMAGES_BASE_DIR" ] || CONTAINER_IMAGES_BASE_DIR="$wd/srv_fai_config/files/etc/container_images.conf"

if [ -d "$CONTAINER_IMAGES_BASE_DIR" ]; then
  # Clean up any previous temp directory
  CONTAINER_CACHE="/var/tmp/container_images"
  rm -rf ${CONTAINER_CACHE}
  
  # Process each class configuration file
  for class_conf_file in "$CONTAINER_IMAGES_BASE_DIR"/*; do
    [ -f "$class_conf_file" ] || continue
    
    class_name=$(basename "$class_conf_file")
    echo "Processing container images for class: $class_name"
    
    # Read images from config file (ignore comments and empty lines)
    while IFS= read -r i || [ -n "$i" ]; do
      # Skip empty lines and comments
      [[ -z "$i" || "$i" =~ ^[[:space:]]*# ]] && continue
      # Trim whitespace
      i=$(echo "$i" | xargs)
      [[ -z "$i" ]] && continue
      
      registry=$(echo "$i" | cut -d'/' -f2)
      image=$(echo "$i" | cut -d'/' -f3 | sed s/://g)
      image_path="${CONTAINER_CACHE}/opt/${registry}_${image}.tgz"
      mkdir -p "${CONTAINER_CACHE}/opt/"
      
      # Check if we already have this image for another class
      # If yes, we just copy the existing file, otherwise download
      existing_files=$(find "$image_path" -maxdepth 1 -type f 2>/dev/null | head -1)
      if [ -z "$existing_files" ]; then
        # First time we see this image - download it
        echo "Downloading image: $i"
        "${CONTAINER_ENGINE[@]}" pull "$i"
        "${CONTAINER_ENGINE[@]}" save "$i" | gzip > "$image_path"
      else
        # Image already downloaded - just copy the existing file for this class
        # All classes will have the same image content, we just need the file for fcopy
        cp "$existing_files" "$image_path"
        echo "Reusing existing image: $i (for class $class_name)"
      fi
    done < "$class_conf_file"
  done
  
  # Copy all images to the container after processing all classes
  if [ -d "${CONTAINER_CACHE}" ]; then
    echo "${CONTAINER_ENGINE[@]}" cp ${CONTAINER_CACHE}/. fai-setup:/ext/srv/fai/files/
    "${CONTAINER_ENGINE[@]}" cp ${CONTAINER_CACHE}/. fai-setup:/ext/srv/fai/config/files/
    rm -rf ${CONTAINER_CACHE}
  fi
else
  echo "Warning: container_images.conf directory not found, skipping image import" >&2
fi

# Stopping the container after having added stuff in it
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down

# List user defined Classes
userClasses=$(grep -Ev "^#|^$" "$wd"/user_classes.conf | tr '\n' ',' | sed -e "s/,$//")

# ARM64 or AMD64
arch=$(uname -m)
if [ "$arch" == "aarch64" ]; then
    seapatharch="SEAPATH_ARM64"
else
    seapatharch="SEAPATH_AMD64"
fi
# Creating the mirror
CLASSES="FAIBASE,DEBIAN,GRUB_EFI,SEAPATH_COMMON,SEAPATH_HOST,SEAPATH_ISO,${finalClasses}USERCUSTOMIZATION,${userClasses},${seapatharch},LAST"
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-setup bash -c "\
    cp /etc/fai/apt/keys/* /etc/apt/trusted.gpg.d/ &&\
    fai-mirror -v -c $CLASSES /ext/mirror"

# Creating the ISO
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" run --rm fai-cd /ext/fai-cd -f -m /ext/mirror /ext/seapath.iso

# Retrieving the ISO from the volume
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" up --no-start fai-setup
"${CONTAINER_ENGINE[@]}" cp fai-setup:/ext/seapath.iso $output_dir/
"${COMPOSECMD[@]}" -f "${COMPOSE_FILE}" down --remove-orphans --volumes

# Removing temporary files
rm -rf "$wd"/build_tmp/*
