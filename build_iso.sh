#!/bin/bash

wd=$(dirname "$0")
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

rm -f $output_dir/seapath.iso
# removing the volume in case it exists from a precedent build operation
docker rm -f fai-setup 2>/dev/null
docker volume rm build_debian_iso_ext 2>/dev/null

set -ex

if [ ! -f "$wd"/etc_fai/grub.cfg ]; then
  cp "$wd"/etc_fai/grub_base.cfg "$wd"/etc_fai/grub.cfg
fi

finalClasses="SEAPATH_CLUSTER,SEAPATH_DBG,SEAPATH_KERBEROS,SEAPATH_COCKPIT,"

if [ "$1" == "--custom" ]; then

  cp "$wd"/etc_fai/grub_base.cfg "$wd"/etc_fai/grub.cfg
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

  addFlagCombination() {
    listFlags=("french" "FRENCH keyboard rather than english" "OFF" "german" "GERMAN keyboard rather than english" "OFF" "dbg" "DEBUG packages" "OFF" "raid" "lvm RAID" "ON" "cockpit" "COCKPIT packages" "OFF" "kerberos" "KERBEROS packages" "OFF" "cluster" "CLUSTER rather than standalone" "ON")
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

# Creating the NFSROOT
# Removing *.profile since we don't use them
# Removing 50-host-classes to prevent DEMO and FAIBASE to be added to the list of classes
# Adding the Bookworm basefiles to that we deploy a Debian v12 distro
# Patches /sbin/install_packages (bug in the process of being corrected upstream)
$COMPOSECMD -f "$wd"/docker-compose.yml run --rm fai-setup bash -c "\
    echo \"fai-setup -v -e -f \" && \
    fai-setup -v -e -f && \
    echo \"rm -f /ext/srv/fai/config/class/50-host-classes\" && \
    rm -f /ext/srv/fai/config/class/50-host-classes && \
    echo \"rm -f /ext/srv/fai/config/class/*.profile\" && \
    rm -f /ext/srv/fai/config/class/*.profile && \
    echo \"SED\" && \
    sed -i -e \"s|-f \\\"\\\$FAI_ROOT/usr/sbin/apt-cache|-f \\\"\\\$FAI_ROOT/usr/bin/apt-cache|\" /ext/nfsroot/sbin/install_packages && \
    sed -i -e \"s/ --allow-change-held-packages//\" /ext/nfsroot/sbin/install_packages && \
    echo \"wget -O /ext/srv/fai/config/basefiles/BOOKWORM64.tar.xz https://fai-project.org/download/basefiles/BOOKWORM64.tar.xz\" && \
    wget -O /ext/srv/fai/config/basefiles/BOOKWORM64.tar.xz https://fai-project.org/download/basefiles/BOOKWORM64.tar.xz"

# Starting the container to add stuff in it
$COMPOSECMD -f "$wd"/docker-compose.yml up --no-start fai-setup

# Adding the SEAPATH workspace
docker cp "$wd"/srv_fai_config/. fai-setup:/ext/srv/fai/config/

# Stopping the container after having added stuff in it
$COMPOSECMD -f "$wd"/docker-compose.yml down

# Creating the mirror
CLASSES="FAIBASE,DEBIAN,GRUB_EFI,SEAPATH_COMMON,${finalClasses}LAST"
$COMPOSECMD -f "$wd"/docker-compose.yml run --rm fai-setup bash -c "\
    cp /etc/fai/apt/keys/* /etc/apt/trusted.gpg.d/ &&\
    fai-mirror -c $CLASSES /ext/mirror"

# Creating the ISO
$COMPOSECMD -f "$wd"/docker-compose.yml run --rm fai-cd fai-cd -f -m /ext/mirror /ext/seapath.iso

# Retrieving the ISO from the volume
$COMPOSECMD -f "$wd"/docker-compose.yml up --no-start fai-setup
docker cp fai-setup:/ext/seapath.iso $output_dir/
$COMPOSECMD -f "$wd"/docker-compose.yml down --remove-orphans

# Removing the volume
docker volume rm build_debian_iso_ext
