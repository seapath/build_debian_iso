# build_debian_iso
Code to build a debian seapath ISO file using FAI Project

On a linux machine with docker and docker-compose, building the iso file should be possible by simply running 
```
<path_to_build_debian_iso>/build_iso.sh
```

from the directory where you want the .iso file stored.


Some customization you will want to make before building:

- change the authorized_keys files (user and root) with your own --> srv_fai_config/scripts/SEAPATH/40-networking
- change the unprivileged user name and passwd, as well as the root passwd for the deployed server --> class/SEAPATH.var (right now all passwords are "toto")
- change the "FAI" password (used to connect to the server when it's being deployed with the "fai" username and "toto" as a password) --> etc_fai/nfsroot.conf
