FROM debian
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install fai-server fai-doc && \
    apt-get -y install reprepro xorriso squashfs-tools vim
