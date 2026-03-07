# ----------------------------------
# Environment: redis 5
# Note: Redis 5 is EOL. This image uses Redis 6 bookworm base
# with compatibility for users who need the redis:5 yolk tag.
# Consider migrating to redis:7 or redis:8.
# ----------------------------------
FROM    --platform=$TARGETOS/$TARGETARCH redis:6-bookworm

LABEL   author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV     DEBIAN_FRONTEND=noninteractive

RUN     apt-get -y update && \
        apt-get -y upgrade && \
        apt-get -y install --no-install-recommends iproute2 && \
        apt-get clean && rm -rf /var/lib/apt/lists/* && \
        useradd -d /home/container -m container -s /bin/bash

USER    container
ENV     USER=container HOME=/home/container
WORKDIR /home/container

COPY    ../entrypoint.sh /entrypoint.sh
CMD     ["/bin/bash", "/entrypoint.sh"]
