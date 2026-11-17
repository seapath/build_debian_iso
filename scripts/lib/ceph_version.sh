#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve Ceph version and download cephadm / container image at build time.
#
# Version resolution order:
#   1. CEPH_VERSION environment variable
#   2. usercustomization/class/ceph.version (not tracked by git)
#   3. latest stable release of the CEPH_MAJOR series from download.ceph.com,
#      capped at CEPH_MAX_VERSION

_ceph_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${REPO_ROOT:-$(cd "$_ceph_lib_dir/../.." && pwd)}"
CEPH_VERSION_OVERRIDE_FILE="${REPO_ROOT}/usercustomization/class/ceph.version"

# Since 20.2.4 (and 19.2.6), which fix CVE-2025-30156, a newly bootstrapped
# cluster creates aes256k keys, client.admin included. Debian 13 cannot read
# them: ceph-common and librbd 18.2.7 fail with "Malformed input", and the
# kernel RBD and CephFS clients only understand aes256k from Linux 7.0 on,
# while Debian 13 ships 6.12. Ceph 21 (umbrella) has the same behaviour.
# Stay on Ceph 20 and cap it at 20.2.3, the last release that still creates
# aes keys. CEPH_MAX_VERSION overrides the cap, an empty value removes it.
CEPH_MAJOR="${CEPH_MAJOR:-20}"
if [ "$CEPH_MAJOR" = 20 ]; then
    CEPH_MAX_VERSION="${CEPH_MAX_VERSION-20.2.3}"
fi

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
    if [ -n "${CEPH_MAX_VERSION:-}" ] \
        && ! [[ "$CEPH_MAX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: invalid CEPH_MAX_VERSION '$CEPH_MAX_VERSION'" >&2
        return 1
    fi

    # download.ceph.com fails transiently from CI runners: retry, and show
    # curl's error when it still fails.
    local index versions version
    if ! index=$(
        curl -sSfL --connect-timeout 20 --retry 5 --retry-delay 10 \
            --retry-all-errors https://download.ceph.com/
    ); then
        echo "Error: could not fetch the Ceph release index from https://download.ceph.com/" >&2
        return 1
    fi
    versions=$(
        printf '%s\n' "$index" \
            | grep -oE "rpm-${CEPH_MAJOR}\\.2\\.[0-9]+" \
            | sed 's/rpm-//' \
            | sort -Vu
    )
    CEPH_VERSION=
    # Read line by line: callers may change IFS (generate_seapath_image.sh
    # sets it to a comma), which would break word splitting on $versions.
    while IFS= read -r version; do
        [ -n "$version" ] || continue
        if [ -n "${CEPH_MAX_VERSION:-}" ] \
            && [ "$(printf '%s\n%s\n' "$version" "$CEPH_MAX_VERSION" | sort -V | tail -1)" != "$CEPH_MAX_VERSION" ]; then
            continue
        fi
        CEPH_VERSION="$version"
    done <<< "$versions"

    if [ -z "$CEPH_VERSION" ]; then
        echo "Error: could not determine the latest stable Ceph ${CEPH_MAJOR} version${CEPH_MAX_VERSION:+ up to ${CEPH_MAX_VERSION}}" >&2
        return 1
    fi

    echo "Using latest stable Ceph version${CEPH_MAX_VERSION:+ up to ${CEPH_MAX_VERSION}}: ${CEPH_VERSION}" >&2
}

# The helpers below call resolve_ceph_version in the current shell before any
# command substitution, so that CEPH_VERSION is resolved once and reused, and
# so that a failure stops them instead of producing an empty version.
cephadm_download_url() {
    resolve_ceph_version || return 1
    echo "https://download.ceph.com/rpm-${CEPH_VERSION}/el9/noarch/cephadm"
}

ceph_container_image() {
    resolve_ceph_version || return 1
    echo "quay.io/ceph/ceph:v${CEPH_VERSION}"
}

download_cephadm() {
    local dest="$1"
    local url
    resolve_ceph_version || return 1
    url=$(cephadm_download_url) || return 1
    echo "Downloading cephadm from ${url}"
    wget -O "$dest" "$url"
}

patch_ceph_container_image() {
    local conf_file="$1"
    local image tmp

    resolve_ceph_version || return 1
    image=$(ceph_container_image) || return 1

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
