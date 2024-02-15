# build_debian_iso

![ShellCheck](https://github.com/seapath/build_debian_iso/actions/workflows/shellcheck.yml/badge.svg)

Code to build a debian seapath ISO file using FAI Project

On a linux machine with docker and docker-compose, building the iso file should be possible by simply running
```
<path_to_build_debian_iso>/build_iso.sh
```

from the directory where you want the .iso file stored.
Note that this iso is only to be used on UEFI systems. Legacy BIOS is not supported on SEAPATH.

However please checkout the Customization section first. There are some things that must be done before building.

## Customization
Some customization you will want to make before building.
First, copy the srv_fai_config/class/SEAPATH_COMMON.var.defaults file to srv_fai_config/class/SEAPATH_COMMON.var
You will make your changes in this new file.

### Mandatory
**change the authorized_keys files (user and root) with your own**
* update the file `srv_fai_config/class/SEAPATH_COMMON.var` and replace "myrootkey", "myuserkey"  and "ansiblekey" by yours

### Optional
**changes in the the unprivileged user name and passwd, as well as the root passwd for the deployed server**
* update the file `srv_fai_config/class/SEAPATH_COMMON.var` (right now all passwords are "toto")
more information about password hash : https://linuxconfig.org/how-to-hash-passwords-on-linux

**keyboard Layout:**
* HOST: update the list of classes in srv_fai_config/class/99-seapath to remove the FRENCH class if you prefer an english keyboard layout ;)
* VM: update the list of classes (CLASSES variable) in build_qcow2.sh script to remove the FRENCH class if you prefer an english keyboard layout ;)
* you can create your own class for debconf customization if you want

**other changes in `srv_fai_config/class/SEAPATH_COMMON.var`**
* TIMEZONE, KEYMAP, apt_cdn: feel free to set you regionalized settings, it's all too french by default :)
* APTPROXY: in case your deployed host will need some proxy to access the debian mirror
* REMOTENIC, REMOTEADDR, REMOTEGW: if you want networking to be available right after deployement set ip/gateway to a specified niv (ie: ens0, enp0s1...)
* SERVER, LOGUSER: if you want the installation logs to be uploaded, using SCP, to a server, for which the login username will be LOGUSER and the password "fai"

more info: https://fai-project.org/fai-guide

**installing a debug image:**

A debug image with more debug packages installed is available through the grub menu.\
All it does is add "dbg" to the list of FAI_FLAGS.


**installing a kerberos image:**

An alternative flavor contains kerberos in order to deploy users within more complex authentication servers.\
It is available through the grub menu. All it does is add "kerberos" to the list of FAI_FLAGS.


**installing a image with soft raid (lvmraid) partitioning:**

A alternative flavor exists that will create a disk partitioning with RAID1 (lvmraid): it requires 2 disks of at least 350GB.\
It is available through the grub menu. All it does is add "raid" to the list of FAI_FLAGS


**using multiple extra features:**

You can choose to deploy the image with several of those extra features. \
For example if you want all of them, just add "raid,dbg,kerberos" to the list of FAI_FLAGS in the grub config.


## Build a Virtual Machine image

To build a basic VM for the SEAPATH project, simply launch the script `build_qcow2.sh` from the directory where you want the .qcow2 file to be stored (the build host must use UEFI).

Please refer to the configuration section above. To customize the Virtual Machine properly, the file SEAPATH_COMMON.var must be filled.

## Add cockpit web UI to host machine

To add the Cockpit web UI inside host image, you can add the `SEAPATH_COCKPIT` class to the list of classes added:
    - In `99-seapath` file: `echo DEBIAN FAIBASE FRENCH BOOKWORM64 SEAPATH_COMMON SEAPATH_HOST SEAPATH_COCKPIT`
