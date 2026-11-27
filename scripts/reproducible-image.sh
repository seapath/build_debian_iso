#!/bin/bash
# reproducible-image.sh IMAGE
#
# Rebuild a raw disk image made by fai-diskimage so that its bytes depend only
# on its content and on SOURCE_DATE_EPOCH.
#
# fai-diskimage installs into file systems mounted by the kernel, inside LVM
# volumes created during the build. The result can never be the same twice:
# the kernel records the time of every operation and places the data blocks
# where it wants, and LVM records the build host and the time in its metadata.
#
# This script keeps the layout and the identifiers of the image (partitions,
# LVM volumes, UUIDs of the file systems) and writes everything again:
#   - partition table: sfdisk, with identifiers derived from SOURCE_DATE_EPOCH
#   - ext4:            mke2fs -d, from the files of the original file system.
#                      Files keep their modification time, unless it is later
#                      than SOURCE_DATE_EPOCH.
#   - FAT (EFI):       mkfs.vfat --invariant and mtools
#   - swap:            mkswap
#   - LVM metadata:    copied, then normalized by lvm-normalize-metadata.py
# It then checks that the new image contains the same files as the original
# one, and replaces the original image.
#
# Supported layout: a GPT disk with FAT, ext4 and swap partitions, and LVM
# physical volumes with linear logical volumes that contain ext4 or swap.
# An image with another layout is left as fai-diskimage made it, with a
# warning. Runs as root, in the FAI build container.

set -euo pipefail
img=$1
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is not set}"
export TZ=UTC LC_ALL=C MTOOLS_SKIP_CHECK=1
lvmnorm=$(dirname "$(readlink -f "$0")")/lvm-normalize-metadata.py

work=$(mktemp -d "$(dirname "$img")/reproducible-image.XXXXXX")
new=$work/new.raw
mnt=$work/mnt
mkdir -p $mnt
loop=""
vgs_active=""

cleanup() {
    set +e
    mountpoint -q $mnt && umount $mnt
    for vg in $vgs_active; do vgchange -an $vg > /dev/null 2>&1; done
    [ -n "$loop" ] && losetup -d $loop
    rm -rf $work
}
trap cleanup EXIT
die() { echo "reproducible-image: $*" >&2; exit 1; }
unsupported() {
    echo "reproducible-image: WARNING: $*." >&2
    echo "reproducible-image: $img is left as fai-diskimage made it: it is not reproducible." >&2
    exit 0
}

attach() {   # attach FILE: loop device with partitions, LVM volumes active
    loop=$(losetup -P -r -f --show "$1")
    udevadm settle 2>/dev/null || true
    # pvs fails for the partitions that are not LVM physical volumes
    vgs_active=$({ pvs --noheadings -o vg_name ${loop}p* 2>/dev/null || true; } | sort -u | xargs)
    for vg in $vgs_active; do vgchange -ay $vg > /dev/null; done
}
detach() {
    for vg in $vgs_active; do vgchange -an $vg > /dev/null; done
    losetup -d $loop
    loop="" vgs_active=""
}
blk() { blkid -p -o value -s "$1" "$2" 2>/dev/null || true; }
le() { od -An -tu"$3" -j"$2" -N"$3" "$1" | tr -d ' '; }   # le DEVICE OFFSET BYTES: little-endian number
sb() { dumpe2fs -h "$2" 2>/dev/null | sed -n "s/^$1: *//p"; }

# List the file systems of the attached image: name, device, type.
# The name does not depend on the number of the loop device.
volumes() {
    local dev
    for dev in "$loop"p* $(for vg in $vgs_active; do ls /dev/$vg/* 2>/dev/null; done); do
        case $(blk TYPE $dev) in
            ext4|vfat) echo "$(echo ${dev#"$loop"} | sed 's|^/dev/||; s|/|-|g') $dev $(blk TYPE $dev)" ;;
        esac
    done
}

# Describe the files of all the file systems: used to check the new image
describe() {   # describe OUTDIR
    local name dev type
    mkdir -p "$1"
    volumes | while read -r name dev type; do
        if [ $type = ext4 ]; then
            mount -o ro,noload $dev $mnt
            # what mke2fs must have created like the original mkfs.ext4
            dumpe2fs -h $dev 2>/dev/null | grep -E '^(Filesystem volume name|Filesystem UUID|Filesystem features|Default mount options|Inode count|Block count|Reserved block count|Block size|Inode size|Default directory hash|Maximum mount count|Check interval|Total journal size):' > "$1/$name.superblock"
        else
            mount -o ro $dev $mnt
            # FAT parameters: UEFI firmware is stricter than Linux about them.
            # Byte 65 is a flag set while the file system is mounted.
            od -An -tx1 -N90 $dev | tr -d '\n' |
                sed -E 's/^(( [0-9a-f]{2}){65}) [0-9a-f]{2}/\1 --/' > "$1/$name.bootsector"
        fi
        # path, type, permissions, owner, number of hard links, link target;
        # the root directory is included
        (cd $mnt && find . -path ./lost+found -prune -o -printf '%P\t%y %m %U:%G %n %l\n' | sort) > "$1/$name.meta"
        (cd $mnt && find . -type f -printf '%P\t%s\n' | sort) > "$1/$name.size"
        (cd $mnt && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$1/$name.sha256"
        (cd $mnt && { getfattr -R -h -d -m - -e hex . 2>/dev/null || true; }) |
            awk '/^# file: /{f = substr($0, 9); next} NF {print f "\t" $0}' | sort > "$1/$name.xattr"
        umount $mnt
    done
}

# ---------------------------------------------------------------- original
attach "$img"
src=$loop
size=$(blockdev --getsize64 $src)
describe $work/original

truncate -s $size $new

# partition table: same partitions, identifiers derived from SOURCE_DATE_EPOCH
# and from the identifiers of the content of the partitions
seed=$SOURCE_DATE_EPOCH
for part in "$src"p*; do
    seed+=":$(blk UUID $part)"
done
id() { printf 'seapath:%s:%s' "$seed" "$1" | sha256sum | cut -c1-32 |
       sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/' | tr a-f A-F; }
sfdisk -d $src > $work/table.orig
[ "$(sed -n 's/^label: //p' $work/table.orig)" = gpt ] || unsupported "the partition table is not GPT"
n=0
while IFS= read -r line; do
    case $line in
        label-id:*) echo "label-id: $(id gpt)" ;;
        device:*) ;;
        *start=*) n=$((n + 1)); echo "${line#*: }" | sed -E "s/uuid=[0-9A-Fa-f-]+/uuid=$(id gpt:$n)/" ;;
        *) echo "$line" ;;
    esac
done < $work/table.orig > $work/table.new
sfdisk -q $new < $work/table.new

make_ext4() {   # make_ext4 DEVICE OFFSET_IN_BYTES
    local dev=$1 offset=$2 label uuid seed
    label=$(blk LABEL $dev)
    uuid=$(blk UUID $dev)
    # the seed of the directory hashes is random too: derive it from the UUID
    seed=$(printf 'hash:%s' "$uuid" | sha256sum | cut -c1-32 |
           sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')
    mount -o ro,noload $dev $mnt
    mke2fs -q -F -t ext4 \
        -b "$(sb 'Block size' $dev)" -I "$(sb 'Inode size' $dev)" -N "$(sb 'Inode count' $dev)" \
        ${label:+-L "$label"} -U "$uuid" \
        -E "offset=$offset,hash_seed=$seed,root_owner=$(stat -c %u:%g $mnt)" \
        -d $mnt $new "$(( $(blockdev --getsize64 $dev) / 1024 ))k"
    umount $mnt
}

make_swap() {   # make_swap DEVICE OFFSET_IN_BYTES
    local dev=$1 offset=$2 label
    label=$(blk LABEL $dev)
    truncate -s "$(blockdev --getsize64 $dev)" $work/swap
    mkswap -q -U "$(blk UUID $dev)" ${label:+-L "$label"} $work/swap > /dev/null
    dd if=$work/swap of=$new bs=1M seek=$offset oflag=seek_bytes conv=notrunc,sparse status=none
    rm -f $work/swap
}

make_vfat() {   # make_vfat DEVICE OFFSET_IN_BYTES
    local dev=$1 offset=$2 label id fat f
    label=$(blk LABEL $dev)
    id=$(blk UUID $dev | tr -d -)
    fat=$(blk VERSION $dev | tr -d -c 0-9)
    # With --offset, mkfs.vfat chooses the size of the clusters from the size
    # of the whole image: give it the geometry of the original file system.
    mkfs.vfat --invariant -F "$fat" -i "$id" ${label:+-n "$label"} \
        -S "$(le $dev 11 2)" -s "$(le $dev 13 1)" -R "$(le $dev 14 2)" -f "$(le $dev 16 1)" \
        -M "$(le $dev 21 1)" -g "$(le $dev 26 2)/$(le $dev 24 2)" -h "$(le $dev 28 4)" \
        --offset=$((offset / 512)) $new $(( $(blockdev --getsize64 $dev) / 1024 )) > /dev/null 2>&1
    mount -o ro $dev $mnt
    (cd $mnt && find . -mindepth 1 -type d | sort) | while IFS= read -r f; do
        mmd -i "$new@@$offset" "::${f#./}"
    done
    (cd $mnt && find . -type f | sort) | while IFS= read -r f; do
        mcopy -i "$new@@$offset" "$mnt/${f#./}" "::${f#./}"
    done
    umount $mnt
}

make_volume() {   # make_volume DEVICE OFFSET_IN_BYTES
    case $(blk TYPE $1) in
        ext4) make_ext4 $1 $2 ;;
        swap) make_swap $1 $2 ;;
        vfat) make_vfat $1 $2 ;;
        "") ;;
        *) unsupported "$1 contains $(blk TYPE $1), which is not supported" ;;
    esac
}

for part in "$src"p*; do
    start=$(( $(cat /sys/class/block/${part##*/}/start) * 512 ))
    if [ "$(blk TYPE $part)" != LVM2_member ]; then
        make_volume $part $start
        continue
    fi
    # LVM physical volume: label and metadata area, then each logical volume
    vg=$(pvs --noheadings -o vg_name $part | xargs)
    pe_start=$(pvs --noheadings --units b --nosuffix -o pe_start $part | xargs)
    extent=$(vgs --noheadings --units b --nosuffix -o vg_extent_size $vg | xargs)
    dd if=$part of=$new bs=1M count=$pe_start iflag=count_bytes seek=$start oflag=seek_bytes conv=notrunc status=none
    python3 $lvmnorm $new $start
    while read -r lv segments type ranges; do
        if [ "$segments" != 1 ] || [ "$type" != linear ]; then
            unsupported "$vg/$lv is not a linear volume with one segment"
        fi
        first=${ranges#*:}; first=${first%-*}
        make_volume /dev/$vg/$lv $((start + pe_start + first * extent))
    done < <(lvs --noheadings -o lv_name,seg_count,segtype,seg_pe_ranges $vg)
done
detach

# the same holes on every file system: a block is allocated only if it has data
fallocate --dig-holes $new

# ---------------------------------------------------------------- checks
attach $new
describe $work/new
volumes | while read -r name dev type; do
    case $type in
        ext4) e2fsck -fn $dev > $work/fsck.log 2>&1 || { cat $work/fsck.log; die "$name: e2fsck found errors"; } ;;
        vfat) fsck.vfat -n $dev > $work/fsck.log 2>&1 || { cat $work/fsck.log; die "$name: fsck.vfat found errors"; } ;;
    esac
done
for vg in $vgs_active; do vgck $vg > /dev/null || die "vgck $vg failed"; done
detach
if ! diff -r $work/original $work/new > $work/diff.log; then
    head -40 $work/diff.log
    die "the new image does not contain the same files as the original one"
fi
entries=$(cat $work/new/*.meta | wc -l)

mv $new "$img"
echo "reproducible-image: $img rebuilt, $entries files and directories checked against the original image"
