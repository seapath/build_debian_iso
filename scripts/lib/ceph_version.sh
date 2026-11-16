#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve Ceph version and download cephadm / container image at build time.
#
# Version resolution order:
#   1. CEPH_VERSION environment variable
#   2. usercustomization/class/ceph.version (not tracked by git)
#   3. latest stable release of the CEPH_MAJOR series from download.ceph.com,
#      capped at CEPH_MAX_VERSION
#
# The host packages (ceph-common, librbd1...) come from the download.ceph.com
# repository of that same release, so that they match the cephadm binary and
# the container image embedded in the image.

_ceph_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="${REPO_ROOT:-$(cd "$_ceph_lib_dir/../.." && pwd)}"
CEPH_VERSION_OVERRIDE_FILE="${REPO_ROOT}/usercustomization/class/ceph.version"

# The Ceph series followed by default. Since 20.2.4 a new cluster creates
# aes256k keys, which the Ceph 18 client of Debian 13 cannot read, so the
# host clients come from download.ceph.com (ceph_apt_source). That site only
# publishes trixie packages from Ceph 21 (umbrella) on.
CEPH_MAJOR="${CEPH_MAJOR:-21}"

# A build that goes back to the Ceph 20 series stays at 20.2.3, the last
# release that still creates aes keys. CEPH_MAX_VERSION overrides the cap,
# an empty value removes it.
if [ "$CEPH_MAJOR" = 20 ]; then
    CEPH_MAX_VERSION="${CEPH_MAX_VERSION-20.2.3}"
fi

# Suite of the download.ceph.com repository: the Debian release of the image.
CEPH_APT_SUITE="${CEPH_APT_SUITE:-trixie}"

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

    local versions version
    versions=$(
        curl -sf https://download.ceph.com/ \
            | grep -oE "rpm-${CEPH_MAJOR}\\.2\\.[0-9]+" \
            | sed 's/rpm-//' \
            | sort -Vu
    )
    CEPH_VERSION=
    for version in $versions; do
        if [ -n "${CEPH_MAX_VERSION:-}" ] \
            && [ "$(printf '%s\n%s\n' "$version" "$CEPH_MAX_VERSION" | sort -V | tail -1)" != "$CEPH_MAX_VERSION" ]; then
            continue
        fi
        CEPH_VERSION="$version"
    done

    if [ -z "$CEPH_VERSION" ]; then
        echo "Error: could not determine the latest stable Ceph ${CEPH_MAJOR} version${CEPH_MAX_VERSION:+ up to ${CEPH_MAX_VERSION}}" >&2
        return 1
    fi

    echo "Using latest stable Ceph version${CEPH_MAX_VERSION:+ up to ${CEPH_MAX_VERSION}}: ${CEPH_VERSION}" >&2
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

# Set CEPH_APT_URI to the download.ceph.com repository of the Ceph release,
# after checking that it publishes CEPH_APT_SUITE. A missing suite would
# otherwise only show up as Debian's own Ceph 18 packages in the image.
resolve_ceph_apt_uri() {
    resolve_ceph_version || return 1
    CEPH_APT_URI="https://download.ceph.com/debian-${CEPH_VERSION}"
    if ! curl -sfI "${CEPH_APT_URI}/dists/${CEPH_APT_SUITE}/Release" >/dev/null; then
        echo "Error: ${CEPH_APT_URI} has no ${CEPH_APT_SUITE} suite, Ceph ${CEPH_VERSION} packages are not available for this Debian release" >&2
        return 1
    fi
}

# Write the deb822 apt source of the Ceph release to $1.
ceph_apt_source() {
    local dest="$1"

    resolve_ceph_apt_uri || return 1
    cat > "$dest" <<EOF
# Generated by scripts/lib/ceph_version.sh, do not edit.
Types: deb
URIs: ${CEPH_APT_URI}
Suites: ${CEPH_APT_SUITE}
Components: main
EOF
    echo "Ceph apt source written to $dest -> ${CEPH_APT_URI} ${CEPH_APT_SUITE}"
}

# One-line form of the same source, for a classic sources.list.
ceph_apt_line() {
    resolve_ceph_apt_uri || return 1
    echo "deb ${CEPH_APT_URI} ${CEPH_APT_SUITE} main"
}
