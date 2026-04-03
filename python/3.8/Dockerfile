FROM        --platform=$TARGETOS/$TARGETARCH python:3.8-slim-bookworm

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

RUN         apt update \
            && apt -y install git gcc g++ ca-certificates dnsutils curl iproute2 ffmpeg procps tini \
            && (existing=$(getent passwd 1000 | cut -d: -f1) && [ -n "$existing" ] && userdel -r "$existing"; true) && useradd -u 1000 -m -d /home/container -s /bin/bash container

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
