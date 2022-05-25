FROM debian
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install fai-server && \
    apt-get -y install reprepro xorriso squashfs-tools vim
ADD etc_fai /etc/fai/
ADD srv_fai_config /srv/fai/config/

