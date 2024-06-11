FROM debian:12
COPY etc_fai/apt/keys/fai-project.gpg /etc/apt/trusted.gpg.d/
RUN echo "deb [arch=amd64] http://fai-project.org/download bookworm koeln" > /etc/apt/sources.list.d/fai.list && \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install fai-server fai-doc fai-setup-storage && \
    apt-get -y install lftp curl whiptail && \
    apt-get -y install qemu-utils && \
    apt-get -y install reprepro xorriso squashfs-tools vim
