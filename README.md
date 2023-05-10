# build_debian_iso

![ShellCheck](https://github.com/seapath/build_debian_iso/actions/workflows/shellcheck.yml/badge.svg)

Code to build a debian seapath ISO file using FAI Project

On a linux machine with docker and docker-compose, building the iso file should be possible by simply running
```
<path_to_build_debian_iso>/build_iso.sh
```

from the directory where you want the .iso file stored.

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

**other changes in `srv_fai_config/class/SEAPATH_COMMON.var`**
* TIMEZONE, KEYMAP, apt_cdn: feel free to set you regionalized settings, it's all too french by default :)
* APTPROXY: in case your deployed host will need some proxy to access the debian mirror
* REMOTENIC, REMOTEADDR, REMOTEGW: if you want networking to be available right after deployement set ip/gateway to a specified niv (ie: ens0, enp0s1...)
* SERVER, LOGUSER: if you want the installation logs to be uploaded, using SCP, to a server, for which the login username will be LOGUSER and the password "fai"

more info: https://fai-project.org/fai-guide

**installing a debug image**
A debug image with more debug packages installed is available through editing
the default profile in `srv_fai_config/class/seapath.profile`:

```
Default: Seapath_LVM_debug
```

You also need to add the required packages to the fai-mirror in `build_iso.sh`:
```
    CLASSES="DEBIAN,SEAPATH_LVM,FAIBASE,DEMO,SEAPATH_COMMON,SEAPATH_HOST,SEAPATH_NOLVM,GRUB_EFI,SEAPATH_DBG"
```

**installing a kerberos image**
An alternative flavor contains kerberos in order to deploy users within more
complex authentication servers.

A debug image with more debug packages installed is available through editing
the default profile in `srv_fai_config/class/seapath.profile`:

```
Default: Seapath_Kerberos
```

You also need to add the required packages to the fai-mirror in `build_iso.sh`:
```
    CLASSES="DEBIAN,SEAPATH_LVM,FAIBASE,SEAPATH_COMMON,SEAPATH_HOST,SEAPATH_NOLVM,GRUB_EFI,KERBEROS"
```

