# ----------------------------------
# Environment: MongoDB
# ----------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH mongo:7-jammy

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         apt update -y \
            && apt install -y netcat iproute2 \
            && (existing=$(getent passwd 1000 | cut -d: -f1) && [ -n "$existing" ] && userdel -r "$existing"; true) \
            && useradd -u 1000 -m -d /home/container -s /bin/bash container

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
