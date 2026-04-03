FROM        --platform=$TARGETOS/$TARGETARCH python:3.9-slim-bookworm

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

RUN         apt update \
            && apt -y install git gcc g++ ca-certificates dnsutils curl iproute2 ffmpeg procps tini \
            && (userdel node 2>/dev/null; userdel mongodb 2>/dev/null; userdel redis 2>/dev/null; true) && useradd -u 1000 -m -d /home/container -s /bin/bash container

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]