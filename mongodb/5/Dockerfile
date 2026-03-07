# ----------------------------------
# Environment: MongoDB 5
# Note: MongoDB 5 is EOL. This image uses mongo:5-jammy (Ubuntu 22.04)
# for working apt repos. Consider migrating to MongoDB 7 or 8.
# ----------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH mongo:5-jammy

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         apt-get update -y \
            && apt-get install -y --no-install-recommends netcat-openbsd iproute2 \
            && apt-get clean && rm -rf /var/lib/apt/lists/* \
            && useradd -d /home/container -m container -s /bin/bash

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
