# ---------------------------------------------
# Steam Proton image
# Also published as yolks:proton (compat alias for eggs that reference it).
#
# Base must stay new enough for the pinned GE-Proton below. GE-Proton11 needs
# glibc 2.38, and bookworm only has 2.36, so every Proton egg died at startup with
# "could not load ntdll.so: version GLIBC_2.38 not found". Trixie has 2.41.
# ---------------------------------------------
FROM        debian:trixie-slim

LABEL       author="Torsten Widmann" maintainer="info@goover.de"

# Install required packages.
#
# libwine is here for its dependencies, not for Debian's wine: GE-Proton ships its
# own wine binaries but none of the shared libraries they need. Without them the X11
# driver cannot load, so anything that opens a window fails. That is what stopped the
# Visual C++ redistributable installing, which reported it as:
#
#   Wine cannot find the FreeType font library.
#   err:winediag:nodrv_CreateWindow ... no driver could be loaded.
#
# libwine pulls libfreetype6, libfontconfig1, libx11-6 and libxext6 for both
# architectures. gnutls is listed separately because wine looks for it by soname and
# the log named it directly.
RUN         dpkg --add-architecture i386
RUN         apt update
RUN         apt install -y --no-install-recommends \
                wget \
                iproute2 \
                gnupg2 \
                libntlm0 \
                winbind \
                xvfb \
                xauth \
                libncurses-dev:i386 \
                libncurses6 \
                dbus \
                libgdiplus \
                lib32gcc-s1 \
                libwine \
                libwine:i386 \
                libgnutls30t64 \
                libgnutls30t64:i386
RUN         apt install -y \
                alsa-tools \
                libpulse0 \
                pulseaudio \
                libpulse-dev \
                libasound2t64 \
                libao-common \
                gnutls-bin \
                gnupg \
                locales \
                cabextract \
                curl \
                python3 \
                python3-pip \
                python3-setuptools \
                tini \
                file \
                pipx

# Download Proton GE, pinned.
#
# This used to resolve whatever "latest" pointed at. GE-Proton11 then raised its
# glibc floor to 2.38 and every Proton game in the panel stopped starting, with
# nothing in this repo having changed. A Proton bump can break every Proton egg at
# once, so it is a deliberate change now, not a side effect of rebuilding.
#
# When bumping: check the release runs on the base image's glibc, and update the
# checksum from the release's own .sha512sum.
ARG         GE_PROTON_VERSION=GE-Proton11-3
ARG         GE_PROTON_SHA512=528ae7831f909c0a4fff5d83889ac6dab3c9706746cd148f05f3064ac042763853d68277e2a815f18f16c17285d5d128864a03c563956c0dce30bafcd16aa77c

RUN         set -eux; \
            curl -fsSLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"; \
            echo "${GE_PROTON_SHA512}  ${GE_PROTON_VERSION}.tar.gz" | sha512sum -c -; \
            tar -xzf "${GE_PROTON_VERSION}.tar.gz" -C /usr/local/bin/ --strip-components=1; \
            rm "${GE_PROTON_VERSION}.tar.gz"; \
            test -x /usr/local/bin/proton

# Proton Fix machine-id
RUN         rm -f /etc/machine-id
RUN         dbus-uuidgen --ensure=/etc/machine-id
RUN         rm /var/lib/dbus/machine-id
RUN         dbus-uuidgen --ensure

# Setup Protontricks
RUN         pipx install protontricks

# Set up Winetricks, from the project itself rather than a third party's fork
RUN	        wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
            && chmod +x /usr/sbin/winetricks

# Install rcon
RUN         cd /tmp/ \
            && curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz \
            && tar xvf rcon.tar.gz \
            && mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/
            
# Setup user and working directory
RUN         useradd -m -d /home/container -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL  SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]