# ----------------------------------
# Environment: MongoDB 5
# Note: MongoDB 5 is EOL. This image uses mongo:5-jammy (Ubuntu 22.04)
# for working apt repos. Consider migrating to MongoDB 7 or 8.
# ----------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH mongo:5.0-focal

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         apt-get update -y \
            && apt-get install -y --no-install-recommends netcat-openbsd iproute2 \
            && apt-get clean && rm -rf /var/lib/apt/lists/* \
            && (existing=$(getent passwd 1000 | cut -d: -f1) && [ -n "$existing" ] && userdel -r "$existing"; true) \
            && useradd -u 1000 -m -d /home/container -s /bin/bash container

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
