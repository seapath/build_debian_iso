FROM debian:trixie
COPY etc_fai/apt/keys/fai-project.gpg /etc/apt/trusted.gpg.d/
RUN echo "deb http://fai-project.org/download trixie koeln" > /etc/apt/sources.list.d/fai.list && \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install fai-server fai-doc fai-setup-storage && \
    apt-get -y install lftp curl whiptail patch && \
    apt-get -y install qemu-utils && \
    apt-get -y install reprepro xorriso squashfs-tools vim udev

# Syft is a tool for SBOM generation
# Pin version to avoid querying GitHub's releases API at build time
ARG SYFT_VERSION=v1.18.1
RUN curl -sSfL https://get.anchore.io/syft | sh -s -- -b /usr/local/bin ${SYFT_VERSION}
