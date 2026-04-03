# ----------------------------------
# Environment: redis
# ----------------------------------
FROM    --platform=$TARGETOS/$TARGETARCH redis:6-bookworm

LABEL   author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV     DEBIAN_FRONTEND=noninteractive

RUN     apt -y update && \
        apt -y upgrade && \
        apt -y install iproute2 && \
        (existing=$(getent passwd 1000 | cut -d: -f1) && [ -n "$existing" ] && userdel -r "$existing"; true) && useradd -u 1000 -d /home/container -m container -s /bin/bash

USER    container
ENV     USER=container HOME=/home/container
WORKDIR /home/container

COPY    ../entrypoint.sh /entrypoint.sh
CMD     ["/bin/bash", "/entrypoint.sh"]
