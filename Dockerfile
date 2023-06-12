FROM debian:bookworm
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install fai-server fai-doc fai-setup-storage && \
    apt-get -y install qemu-utils && \
    apt-get -y install reprepro xorriso squashfs-tools vim
