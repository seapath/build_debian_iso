#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve Ceph version and download cephadm / container image at build time.
#
# Version resolution order:
#   1. CEPH_VERSION environment variable
#   2. usercustomization/class/ceph.version (not tracked by git)
#   3. latest stable release of the CEPH_MAJOR series from download.ceph.com

_ceph_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${REPO_ROOT:-$(cd "$_ceph_lib_dir/../.." && pwd)}"
CEPH_VERSION_OVERRIDE_FILE="${REPO_ROOT}/usercustomization/class/ceph.version"

# Debian 13 stays on Ceph 20 (tentacle). Ceph 21 (umbrella) rotates the
# daemon keys to the aes256k type and keeps warning until the client keys
# follow, but the kernel RBD and CephFS clients only understand aes256k from
# Linux 7.0 on, and Debian 13 ships 6.12. Move to 21 with Debian 14.
CEPH_MAJOR="${CEPH_MAJOR:-20}"

_load_ceph_version_from_file() {
    local file="$1"
    local version

    [ -f "$file" ] || return 1

    version=$(
        grep -Ev '^[[:space:]]*(#|$)' "$file" | head -1 | tr -d '[:space:]'
    )
    if [ -z "$version" ]; then
        return 1
    fi
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: invalid Ceph version '$version' in $file" >&2
        return 1
    fi

    CEPH_VERSION="$version"
}

resolve_ceph_version() {
    if [ -n "${CEPH_VERSION:-}" ]; then
        echo "Using Ceph version from CEPH_VERSION: ${CEPH_VERSION}" >&2
        return 0
    fi

    if _load_ceph_version_from_file "$CEPH_VERSION_OVERRIDE_FILE"; then
        echo "Using Ceph version from $CEPH_VERSION_OVERRIDE_FILE: ${CEPH_VERSION}" >&2
        return 0
    fi

    # Ceph publishes development (x.0.z) and release candidate (x.1.z) builds
    # next to the stable ones, and they sort above the latest stable release as
    # soon as a new major is being prepared. Only consider the stable channel
    # (x.2.z), so that a build never silently lands on a pre-release, and
    # only the CEPH_MAJOR series, so that it never silently changes major.
    if ! [[ "$CEPH_MAJOR" =~ ^[0-9]+$ ]]; then
        echo "Error: invalid CEPH_MAJOR '$CEPH_MAJOR'" >&2
        return 1
    fi
    CEPH_VERSION=$(
        curl -sf https://download.ceph.com/ \
            | grep -oE "rpm-${CEPH_MAJOR}\\.2\\.[0-9]+" \
            | sed 's/rpm-//' \
            | sort -Vu \
            | tail -1
    )

    if [ -z "$CEPH_VERSION" ]; then
        echo "Error: could not determine the latest stable Ceph ${CEPH_MAJOR} version" >&2
        return 1
    fi

    echo "Using latest stable Ceph version: ${CEPH_VERSION}" >&2
}

cephadm_download_url() {
    resolve_ceph_version
    echo "https://download.ceph.com/rpm-${CEPH_VERSION}/el9/noarch/cephadm"
}

ceph_container_image() {
    resolve_ceph_version
    echo "quay.io/ceph/ceph:v${CEPH_VERSION}"
}

download_cephadm() {
    local dest="$1"
    local url
    url=$(cephadm_download_url)
    echo "Downloading cephadm from ${url}"
    wget -O "$dest" "$url"
}

patch_ceph_container_image() {
    local conf_file="$1"
    local image tmp

    image=$(ceph_container_image)

    if [ ! -f "$conf_file" ]; then
        echo "Warning: $conf_file not found, skipping Ceph image patch" >&2
        return 0
    fi

    tmp=$(mktemp)
    grep -v '^quay\.io/ceph/ceph:' "$conf_file" > "$tmp" || true
    echo "$image" >> "$tmp"

    if [ -w "$conf_file" ]; then
        mv "$tmp" "$conf_file"
    else
        sudo mv "$tmp" "$conf_file"
    fi
    echo "Patched Ceph container image in $conf_file -> $image"
}
