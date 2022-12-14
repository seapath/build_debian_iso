# build_debian_iso
Code to build a debian seapath ISO file using FAI Project

On a linux machine with docker and docker-compose, building the iso file should be possible by simply running 
```
<path_to_build_debian_iso>/build_iso.sh
```

from the directory where you want the .iso file stored.

## Customization 
Some customization you will want to make before building.
First, copy the srv_fai_config/class/SEAPATH.var.defaults file to srv_fai_config/class/SEAPATH.var
You will make your changes in this new file.

### Mandatory
**change the authorized_keys files (user and root) with your own**   
* update the file `srv_fai_config/class/SEAPATH.var` and replace "myrootkey", "myuserkey"  and "ansiblekey" by yours

### Optional
**changes in the the unprivileged user name and passwd, as well as the root passwd for the deployed server**  
* update the file `srv_fai_config/class/SEAPATH.var` (right now all passwords are "toto")  
more information about password hash : https://linuxconfig.org/how-to-hash-passwords-on-linux    

**other changes in `srv_fai_config/class/SEAPATH.var`**
* TIMEZONE, KEYMAP, apt_cdn: feel free to set you regionalized settings, it's all too french by default :)
* APTPROXY: in case your deployed host will need some proxy to access the debian mirror
* REMOTENIC, REMOTEADDR, REMOTEGW: if you want networking to be available right after deployement set ip/gateway to a specified niv (ie: ens0, enp0s1...)
* SERVER, LOGUSER: if you want the installation logs to be uploaded, using SCP, to a server, for which the login username will be LOGUSER and the password "fai"

more info: https://fai-project.org/fai-guide

