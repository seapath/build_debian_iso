#!/usr/bin/env sh

set -e

cd "$(dirname "$0")"
cp -f grub.cfg ../etc_fai/grub.cfg
cp -f class_USERCUSTOMIZATION.var ../usercustomization/class/USERCUSTOMIZATION.var
cd ..
./build_iso.sh
./build_qcow2.sh
