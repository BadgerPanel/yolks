# ---------------------------------------------
# BONELAB Fusion headless relay
# Carries Steam and a virtual display, not the game.
# ---------------------------------------------
FROM        --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL       org.opencontainers.image.description="Headless BONELAB Fusion relay server for Pterodactyl"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\n' \
                > /etc/apt/apt.conf.d/99-badger-retries

# Steam's dependencies live in contrib and non-free.
RUN         if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
                sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' \
                    /etc/apt/sources.list.d/debian.sources; \
            else \
                sed -i 's/ main$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list; \
            fi

# i386 is required: the Steam client bootstrap is still 32-bit. xz-utils is what
# unpacks that bootstrap, and its absence is a silent failure inside steam.sh.
RUN         dpkg --add-architecture i386 \
            && apt-get update \
            && apt-get install -y --no-install-recommends \
                ca-certificates curl wget jq tini xvfb xz-utils \
                iproute2 net-tools tzdata locales procps file \
                libgcc-s1 lib32gcc-s1 libc6 libc6:i386 libstdc++6 libstdc++6:i386 \
                libgl1:i386 libdrm2:i386 \
                dbus-x11 \
                x11vnc novnc websockify \
                libnss-wrapper gettext-base \
            && test -e /usr/lib/i386-linux-gnu/libGL.so.1 \
            && command -v dbus-launch \
            && command -v x11vnc \
            && command -v websockify \
            && test -d /usr/share/novnc \
            && test -e /usr/lib/i386-linux-gnu/libdrm.so.2 \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/*

# steamcmd still accepts a command-line login where the client no longer does, so
# it is what obtains the credentials the client then reuses. Valve's tarball
# rather than the Debian package, which stops to ask about its licence.
RUN         mkdir -p /opt/steamcmd \
            && curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
                | tar xz -C /opt/steamcmd \
            && chmod -R a+rX /opt/steamcmd \
            && test -x /opt/steamcmd/steamcmd.sh

# Runtime only; the server is published framework-dependent.
RUN         wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
            && chmod +x /tmp/dotnet-install.sh \
            && /tmp/dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir /usr/share/dotnet \
            && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
            && rm /tmp/dotnet-install.sh

# Installed with apt rather than unpacked with dpkg -x, so Valve's declared
# dependencies are actually resolved. Steam's runtime then unpacks into the volume
# on first start, which is what the egg's disk requirement is for.
RUN         curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steam.deb -o /tmp/steam.deb \
            && apt-get update \
            && apt-get install -y --no-install-recommends /tmp/steam.deb \
            && apt-get update \
            && apt-get install -y --no-install-recommends \
                steam-libs-amd64 steam-libs-i386 libgl1-mesa-dri libgl1-mesa-dri:i386 \
            && rm /tmp/steam.deb \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/* \
            && dpkg -s steam-libs-amd64 > /dev/null \
            && dpkg -s steam-libs-i386 > /dev/null \
            && command -v steam

# Steam's Debian packaging runs steamdeps on first launch, which opens an xterm
# and blocks on "Press return to continue". Nothing can answer that in a container,
# so the client never starts. Dependencies are baked into this image, so the check
# has nothing useful to do anyway.
RUN         echo '#!/bin/sh' > /usr/bin/steamdeps \
            && echo 'exit 0' >> /usr/bin/steamdeps \
            && chmod +x /usr/bin/steamdeps

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
