# ---------------------------------------------
# BONELAB Fusion headless relay
#
# Carries Steam and a virtual display, not the game. The relay reimplements the
# Fusion wire format, so no BONELAB files are ever downloaded.
# ---------------------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL       org.opencontainers.image.description="Headless BONELAB Fusion relay server for Pterodactyl"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\n' \
                > /etc/apt/apt.conf.d/99-badger-retries

# i386 is required: the Steam client bootstrap is still 32-bit.
RUN         dpkg --add-architecture i386 \
            && apt-get update \
            && apt-get install -y --no-install-recommends \
                ca-certificates curl wget jq tini xvfb \
                iproute2 net-tools tzdata locales procps \
                libgcc-s1 lib32gcc-s1 libc6 libc6:i386 libstdc++6 libstdc++6:i386 \
                libnss-wrapper gettext-base \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/*

# .NET 9 runtime only. The server is published framework-dependent, so no SDK.
RUN         wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
            && chmod +x /tmp/dotnet-install.sh \
            && /tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir /usr/share/dotnet \
            && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
            && rm /tmp/dotnet-install.sh

# Steam client bootstrap. Its runtime unpacks into the volume on first start,
# which is why the egg asks for a few GB of disk.
RUN         mkdir -p /opt/steam \
            && curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steam.deb -o /tmp/steam.deb \
            && dpkg -x /tmp/steam.deb /opt/steam \
            && rm /tmp/steam.deb \
            && ln -s /opt/steam/usr/bin/steam /usr/bin/steam

ENV         NSS_WRAPPER_PASSWD=/tmp/passwd NSS_WRAPPER_GROUP=/etc/group

RUN         useradd -m -d /home/container -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL  SIGINT

COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
