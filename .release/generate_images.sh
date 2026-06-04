#!/usr/bin/env bash

set -euo pipefail

PUBLISH=false

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [--publish] [-h|--help]

Build SEAPATH release artifacts (ISO, QCOW2, and standalone/cluster/observer
rootfs images), rename them with the current git-described version, and
optionally publish them to the matching GitHub release.

Options:
  --tag        Use this specific tag instead of guessing it from the git
               describe command.
  --publish    Upload the renamed artifacts to the GitHub release matching
               the current tag. Requires being on an exact, clean tag and
               that the release already exists on GitHub.
  -h, --help   Show this help message.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --publish)
            PUBLISH=true
            shift
            ;;
        --tag)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")"
cp -f grub.cfg ../etc_fai/grub.cfg
cp -f class_USERCUSTOMIZATION.var ../usercustomization/class/USERCUSTOMIZATION.var
cd ..

if ! command -v bmaptool >/dev/null; then
    echo "Error: bmaptool is not installed. Install it before running this script." >&2
    exit 1
fi

if [ -z "$VERSION" ]; then
  VERSION=$(git describe --tags --dirty)
fi

if $PUBLISH; then
    if ! command -v gh >/dev/null; then
        echo "Error: gh (GitHub CLI) is not installed. Install it before using --publish." >&2
        exit 1
    fi
    if ! TAG=$(git describe --tags --exact-match 2>/dev/null); then
        echo "Error: --publish requires being on an exact git tag (got: ${VERSION})." >&2
        exit 1
    fi
    if [[ "$(git describe --tags --exact-match --dirty)" == *-dirty ]]; then
        echo "Error: --publish requires a clean worktree (tag ${TAG} is dirty)." >&2
        exit 1
    fi
    if ! gh release view "$TAG" >/dev/null 2>&1; then
        echo "Error: GitHub release ${TAG} does not exist. Create it on GitHub first, then re-run with --publish." >&2
        exit 1
    fi
fi

ISO="seapath-${VERSION}-debian-autoinstaller-fai.iso"
QCOW="seapath-${VERSION}-guest.qcow2"
STANDALONE="seapath-${VERSION}-generic-standalone.rootfs"
CLUSTER="seapath-${VERSION}-generic-cluster.rootfs"
OBSERVER="seapath-${VERSION}-generic-observer.rootfs"

build_role() {
    local role="$1"
    local base="$2"
    shift 2
    ./generate_seapath_image.sh "$role" "$@"
    mv -f seapath.raw.gz   "${base}.raw.gz"
    mv -f seapath.raw.bmap "${base}.raw.bmap"
}

mkdir -p release-files/

./build_iso.sh
mv -f seapath.iso   release-files/"$ISO"

./build_qcow2.sh
mv -f seapath-vm.qcow2  release-files/"$QCOW"

build_role standalone  release-files/"$STANDALONE" -c
build_role cluster     release-files/"$CLUSTER"    -c --ceph-disk
build_role observer    release-files/"$OBSERVER"   -c

if $PUBLISH; then
    gh release upload "$TAG" \
        release-files/"$ISO" \
        release-files/"$QCOW" \
        release-files/"${STANDALONE}.raw.gz" \
        release-files/"${STANDALONE}.raw.bmap" \
        release-files/"${CLUSTER}.raw.gz" \
        release-files/"${CLUSTER}.raw.bmap" \
        release-files/"${OBSERVER}.raw.gz" \
        release-files/"${OBSERVER}.raw.bmap" \
        --clobber
fi
