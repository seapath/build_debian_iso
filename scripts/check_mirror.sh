#!/bin/bash
#
# Check that the mirror built by fai-mirror can install the system.
#
# fai-mirror echoes "Your mirror may be broken" and still returns 0, so a hole in
# the mirror travels into the ISO and only shows up when apt runs on a real
# machine, at the end of an installation. Replay that transaction here: start
# from the package set of base.tar.xz, offer the mirror as the only source, and
# simulate what install_packages will ask apt to do.
#
# Runs inside the fai container. Usage: check_mirror.sh <mirrordir> <classes>

set -eu

mirror=${1:?usage: ${0##*/} <mirrordir> <classes>}
classes=${2:?usage: ${0##*/} <mirrordir> <classes>}

# NFSROOT and FAI_CONFIGDIR, the same way fai-mirror reads them
# shellcheck source=/dev/null
. "${FAI_ETC_DIR:-/etc/fai}/nfsroot.conf"

base="$NFSROOT/var/tmp/base.tar.xz"
if [ ! -f "$base" ]; then
    echo "ERROR: $base not found, cannot tell what the installation starts from." >&2
    exit 1
fi

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/etc/apt/preferences.d" "$root/etc/apt/sources.list.d" \
         "$root/var/lib/apt/lists/partial" "$root/var/cache/apt/archives/partial" \
         "$root/var/log/apt"

# The package set the installation starts from. Versions matter: the packages of
# base.tar.xz are the ones no other package pulls, since they are Essential, and
# they are exactly where a mirror goes inconsistent unnoticed.
tar -xJf "$base" -O ./var/lib/dpkg/status > "$root/status"

# The sources.list fai-cd will write on the CD, derived from the mirror the same
# way, so that the check sees what the installation will see.
for suite in $(find "$mirror" -name "Packages*" | grep binary | \
               sed -e 's/binary-.*//' -e "s#$mirror/*dists/##" | \
               xargs -r -n 1 dirname | sort -u); do
    comp=$(find "$mirror/dists/$suite" -maxdepth 2 -type d -name "binary-*" | \
           sed -e "s#$mirror/*dists/$suite/##" -e 's#/binary-.*##' | \
           sort -u | tr '\n' ' ')
    echo "deb [trusted=yes] file:$mirror $suite $comp"
done > "$root/etc/apt/sources.list"

if [ ! -s "$root/etc/apt/sources.list" ]; then
    echo "ERROR: no Packages file found under $mirror." >&2
    exit 1
fi

aptopt=(-o "Dir::Etc=$root/etc/apt"
        -o "Dir::State=$root/var/lib/apt"
        -o "Dir::State::status=$root/status"
        -o "Dir::State::extended_states=$root/var/lib/apt/lists/extended_states"
        -o "Dir::Cache=$root/var/cache/apt"
        -o "Dir::Log=$root/var/log/apt"
        -o "Acquire::Languages=none"
        -o "APT::Sandbox::User=root")

apt-get "${aptopt[@]}" -qq update

# The list install_packages will hand to apt. It drops through "apt-cache
# dumpavail" the names the repositories do not know, so let it see the mirror
# and nothing else, which is what it sees during an installation.
list=$(aptoptions="${aptopt[*]}" classes="${classes//,/ }" FAI="$FAI_CONFIGDIR" \
       install_packages -l | tr '\n' ' ')

# An empty list would let the simulation pass without testing anything.
count=$(echo "$list" | wc -w)
if [ "$count" -lt 2 ]; then
    echo "ERROR: install_packages -l returned $count package(s) for classes $classes." >&2
    exit 1
fi

echo "Checking that the mirror can install $count packages for classes $classes"

# shellcheck disable=SC2086
if ! apt-get "${aptopt[@]}" -s -y --no-install-recommends install $list \
     > "$root/simulate.log" 2>&1; then
    cat >&2 <<EOF

ERROR: the mirror cannot install the system. The ISO would build, and the
       installation would fail at the end, leaving a machine with no kernel
       and no boot loader.

apt said:

EOF
    tail -n 40 "$root/simulate.log" >&2
    exit 1
fi

# apt resolves the transaction, so check that it also produces a system that
# boots. install_packages silently drops the packages the mirror does not know,
# so a download that failed for the kernel or the boot loader would go through
# the simulation above without a word.
missing=""
grep -q "^Inst linux-image" "$root/simulate.log" || missing="a kernel"
case ",$classes," in
    *,GRUB_EFI,*|*,GRUB_PC,*)
        grep -q "^Inst grub-" "$root/simulate.log" ||
            missing="${missing:+$missing and }a boot loader" ;;
esac

if [ -n "$missing" ]; then
    echo >&2
    echo "ERROR: the installation would not install $missing." >&2
    echo "       The mirror is missing those packages, install_packages drops" >&2
    echo "       what it cannot find and the installation would report success." >&2
    exit 1
fi

echo "Mirror OK: apt resolves the installation from $mirror alone."
