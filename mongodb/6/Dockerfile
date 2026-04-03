# ----------------------------------
# Environment: MongoDB
# ----------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH mongo:6-jammy

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         apt-get update -y \
            && apt-get install -y --no-install-recommends netcat-openbsd iproute2 \
            && apt-get clean && rm -rf /var/lib/apt/lists/* \
            && (userdel node 2>/dev/null; userdel mongodb 2>/dev/null; userdel redis 2>/dev/null; true) && useradd -u 1000 -d /home/container -m container -s /bin/bash

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
