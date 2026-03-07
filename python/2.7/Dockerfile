# Note: Python 2.7 reached EOL January 2020.
# This image provides Python 2.7 on a modern Debian base for legacy compatibility.
# Consider migrating to Python 3.x.
FROM        --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL       author="Michael Parker" maintainer="parker@pterodactyl.io"

RUN         apt-get update \
            && apt-get -y install --no-install-recommends \
                python2 python2-dev \
                git gcc g++ ca-certificates dnsutils curl iproute2 ffmpeg procps tini \
            && ln -sf /usr/bin/python2 /usr/bin/python \
            && curl -sSL https://bootstrap.pypa.io/pip/2.7/get-pip.py -o /tmp/get-pip.py \
            && python2 /tmp/get-pip.py || true \
            && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/get-pip.py \
            && useradd -m -d /home/container container

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
