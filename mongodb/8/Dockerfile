# ----------------------------------
# Environment: MongoDB
# ----------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH mongo:8-noble

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         apt update -y \
            && apt install -y netcat-openbsd iproute2 \
            && (userdel node 2>/dev/null; userdel mongodb 2>/dev/null; userdel redis 2>/dev/null; true) && useradd -u 1000 -d /home/container -m container -s /bin/bash

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
