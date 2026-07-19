# ---------------------------------------------
# Steam Proton image
# Also published as yolks:proton (compat alias for eggs that reference it).
# ---------------------------------------------
FROM        debian:bookworm-slim

LABEL       author="Torsten Widmann" maintainer="info@goover.de"

# Install required packages
RUN         dpkg --add-architecture i386
RUN         apt update
RUN         apt install -y --no-install-recommends \
                wget \
                iproute2 \
                gnupg2 \
                software-properties-common \
                libntlm0 \
                winbind \
                xvfb \
                xauth \
                libncurses5-dev:i386 \
                libncurses6 \
                dbus \
                libgdiplus \
                lib32gcc-s1
RUN         apt install -y \
                alsa-tools \
                libpulse0 \
                pulseaudio \
                libpulse-dev \
                libasound2 \
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

# Download Proton GE.
# Resolve the latest tag from the releases/latest redirect instead of the GitHub
# API: the API is rate-limited on shared Actions runners, and when throttled the
# old one-liner resolved to an empty URL and failed the build with curl exit 3
# ("URL malformed"), which is why this image stopped publishing. The redirect is
# not rate-limited, and -f makes any failure loud instead of writing an error
# page to disk.
RUN         set -eux; \
            TAG="$(curl -fsSI https://github.com/GloriousEggroll/proton-ge-custom/releases/latest \
                   | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}' | sed -E 's#.*/tag/##')"; \
            test -n "$TAG"; \
            curl -fsSLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${TAG}/${TAG}.tar.gz"
RUN         tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1
RUN         rm GE-Proton*.*

# Proton Fix machine-id
RUN         rm -f /etc/machine-id
RUN         dbus-uuidgen --ensure=/etc/machine-id
RUN         rm /var/lib/dbus/machine-id
RUN         dbus-uuidgen --ensure

# Setup Protontricks
RUN         pipx install protontricks

# Set up Winetricks
RUN	        wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/pelican-eggs/winetricks/master/src/winetricks \
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