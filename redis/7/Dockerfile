# ----------------------------------
# Environment: redis
# ----------------------------------
FROM    --platform=$TARGETOS/$TARGETARCH redis:7-bookworm

LABEL   author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV     DEBIAN_FRONTEND=noninteractive

RUN     apt -y update && \
        apt -y upgrade && \
        apt -y install iproute2 && \
        (userdel node 2>/dev/null; userdel mongodb 2>/dev/null; userdel redis 2>/dev/null; true) && useradd -u 1000 -d /home/container -m container -s /bin/bash

USER    container
ENV     USER=container HOME=/home/container
WORKDIR /home/container

COPY    ../entrypoint.sh /entrypoint.sh
CMD     ["/bin/bash", "/entrypoint.sh"]
