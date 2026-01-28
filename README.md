# build_debian_iso

![ShellCheck](https://github.com/seapath/build_debian_iso/actions/workflows/shellcheck.yml/badge.svg)

Code to build a debian SEAPATH self installer ISO file or raw images using FAI Project.

Self installer ISO file can be used to install SEAPATH on physical hardware without any user interaction (using preseed/debconf).
The raw images can be used with [SEAPATH installer](https://github.com/seapath/seapath-installer/) to have an interactive installation of SEAPATH.

These scripts are based on FAI Project (Fully Automated Installation) : https://fai-project.org/ and target the X86_64 and ARM64 architectures with UEFI support.

**Note:** If you want pre-built images instead of building them yourself, you can find them at the [Releases](https://github.com/seapath/build_debian_iso/releases) section of this repository.

## Prerequisites

- A linux host with docker and docker-compose script or the docker compose v2 plugin installed
- At large enough disk space to store the images

## Build the ISO file

On a linux machine with docker and docker-compose, building the iso file should be possible by simply running
```
<path_to_build_debian_iso>/build_iso.sh
```

from the directory where you want the .iso file stored.
Note that this iso is only to be used on UEFI systems. Legacy BIOS is not supported on SEAPATH.

However please checkout the Customization section first. There are some things that must be done before building.

## Generate SEAPATH Debian image for SEAPATH Installer

The script `generate_seapath_image.sh` will create a raw image that can be used with the SEAPATH Installer.

The script can generate images for one of this three roles:
- standalone: a single node installation
- cluster: a hypervisor node that will be part of a cluster
- observer: a node that will be used as an observer in the cluster

The script also support optionals parameters described in the usage message.

## Customization
Some customization you will want to make before building.
For that you can add all the files you need in the build_debian_iso/usercustomization hierarchy, using the USERCUSTOMIZATION class name:
- add your variables in the build_debian_iso/usercustomization/class/USERCUSTOMIZATION.var file
- add your debconf parameters to build_debian_iso/usercustomization/debconf/USERCUSTOMIZATION file
- add your disk config to build_debian_iso/usercustomization/disk_config/USERCUSTOMIZATION file
- add your files to build_debian_iso/usercustomization/files/ hierarchy using USERCUSTOMIZATION as the class name (for example build_debian_iso/usercustomization/files/etc/motd/USERCUSTOMIZATION)
- add your hooks to build_debian_iso/usercustomization/hooks/ using USERCUSTOMIZATION as the class name (for example build_debian_iso/usercustomization/hooks/install.USERCUSTOMIZATION)
- add your package_config to build_debian_iso/usercustomization/package_config/USERCUSTOMIZATION file
- add your scripts to build_debian_iso/usercustomization/scripts using USERCUSTOMIZATION as the class name (for example build_debian_iso/usercustomization/scripts/USERCUSTOMIZATION/88-myscript)

Both folders "build_debian_iso/usercustomization and build_debian_iso/srv_fai_config will be merged into build_debian_iso/build_tmp when building).


### Mandatory
**change the authorized_keys files (user and root) with your own**
* update the file `build_debian_iso/usercustomization/class/USERCUSTOMIZATION.var` and replace "myrootkey", "myuserkey"  and "ansiblekey" by yours

### Optional
**changes in the the unprivileged user name and passwd, as well as the root passwd for the deployed server**
* update the file `build_debian_iso/usercustomization/class/USERCUSTOMIZATION.var` (right now all passwords are "seapath")
more information about password hash : https://linuxconfig.org/how-to-hash-passwords-on-linux

**keyboard Layout:**

Only for self installer ISO (build_iso.sh):

* HOST: by default the keyboard will be US. You can use the FRENCH of GERMAN classes to change this. For any other layout, you can create your own debconf in build_debian_iso/usercustomization/debconf/USERCUSTOMIZATION (or create your own class, see "User-defined classes" below)
* VM: by default the build_qcow2 script will import the FRENCH class, you can override the keyboard layout by creating your own debco nf in build_debian_iso/usercustomization/debconf/USERCUSTOMIZATION.

**other changes in `build_debian_iso/usercustomization/class/USERCUSTOMIZATION.var`**
* TIMEZONE, KEYMAP, apt_cdn: feel free to set you regionalized settings, it's all too french by default :)
* APTPROXY: in case your deployed host will need some proxy to access the debian mirror
* REMOTENIC, REMOTEADDR, REMOTEGW: if you want networking to be available right after deployement set ip/gateway to a specified niv (ie: ens0, enp0s1...)
* SERVER, LOGUSER: if you want the installation logs to be uploaded, using SCP, to a server, for which the login username will be LOGUSER and the password "fai"

**Container Images Customization:**

By default, the ISO includes container images needed for SEAPATH functionality. Each class can have its own list of container images:

* Default configurations are in `srv_fai_config/files/etc/container_images.conf/CLASS_NAME` (e.g., `SEAPATH_CLUSTER`, `SEAPATH_HOST`)
* You can override a class by creating `usercustomization/files/etc/container_images.conf/CLASS_NAME`
* You can add images by creating `usercustomization/files/etc/container_images.conf/USERCUSTOMIZATION`
* Each class has its own file, so they don't override each other - all active classes' images are combined
* The file format is one image per line as `registry/image:tag` (e.g., `quay.io/ceph/ceph:v20.2.0`)
* Lines starting with `#` are treated as comments and ignored, as well as empty lines

During installation, the script reads all configuration files from active classes and copies the corresponding image files to `/opt/`. On first boot, all container images from `/opt/*.tgz` are automatically loaded into Podman.

more info: https://fai-project.org/fai-guide

#### Customization the self installer ISO (build_iso.sh)

**Classes and Flags Customization:**

The `build_iso.sh` script supports customization of packages and grub menu items in two ways:

1. **Interactive mode (TUI):** Running `./build_iso.sh --custom` will launch an interactive text user interface where you can:
   * select which package classes to include in the ISO
   * create custom grub menu items with different flag combinations
   * choose the default grub menu entry

2. **Command-line arguments:** For automated builds or non-interactive environments, you can use:
   * `--classes CLASS1,CLASS2,...` to specify which package classes to include (e.g., `--classes SEAPATH_CLUSTER,SEAPATH_DBG`)
   * `--menu "item1;item2;item3"` to specify grub menu items separated by semicolons, where the first item is the default (e.g., `--menu "french,cluster;french;cluster"`)

You can combine these options: `./build_iso.sh --classes SEAPATH_CLUSTER,SEAPATH_DBG --menu "french,cluster;french;cluster"`

Running `./build_iso.sh` without any customization options will include all classes and create a single grub option with cluster mode/lvmraid/english/no_debug/no_kerberos/no_cockpit.

**Classes Customization:**

Packages are organized in several classes:
* SEAPATH_COMMON: packages for all SEAPATH installations (host or guest)
* SEAPATH_HOST: packages for all HOST installations (Cluster mode or standalone)
* SEAPATH_CLUSTER: packages for HOST in Cluster Mode
* SEAPATH_DBG: packages for debug purposes
* SEAPATH_KERBEROS: packages if you need you host to be able to join a kerberos realm / activedirectory domain
* SEAPATH_COCKPIT: packages for cockpit administration

The SEAPATH_COMMON is mandatory, and the SEAPATH_HOST is mandatory for build_iso.sh. The other 4 classes can be enabled/disabled.

The possibles flags to create a grub menu item are:
* french: enables the FRENCH class to set the french keyboard layout. Without this flag, the keyboard is by default (qwerty)
* dbg: enables the SEAPATH_DBG class (installs the debug packages)
* raid: enables the SEAPATH_RAID that will create a disk partitioning with RAID1 (lvmraid): it requires 2 disks.
* cockpit: enables the SEAPATH_COCKPIT class
* kerberos: enables the SEAPATH_KERBEROS class
* cluster: enables the SEAPATH_CLUSTER class. Uncheck this for a standalone installation.
* ceph_disk: to use a dedicated disk for ceph storage (only for cluster mode).

If you want an "english, no debug, no raid, no cockpit, no kerberos, standalone" installation, then you need to uncheck everything, which will result in a fake "noflag" grub menu item being added. This is normal.


#### User-defined classes

The user can manage his own classes by:
- copying the template file user_classes.conf.example to user_classes.conf
- adding the class in the user_classes.conf file (this is for the mirror creation)
- dealing with a numbered script in usercustomization/class/ folder (for example usercustomization/class/99-custom, chmod 755) to use the class (see srv_fai_config/class/99-seapath script for reference)
- adding all the files related to the classes in the usercustomization hierarchy (for example usercustomization/package_config/USERCLASS1)

## Debug a problem

Since the fai process is containerized, build_debian_iso uses a bind mount on /tmp/fai so that all the FAI logs are persisted there on the build host.
This allows the user to debug if the build were to fail for any reason.

## Build a Virtual Machine image

To build a basic VM for the SEAPATH project, simply launch the script `build_qcow2.sh` from the directory where you want the .qcow2 file to be stored (the build host must use UEFI).

Note that the lvm2 package must be installed on your build host.

Please refer to the configuration section above. To customize the Virtual Machine properly, the file SEAPATH_COMMON.var must be filled.
