FROM        --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL       author="Ethan Coward" maintainer="ethan.coward@icloud.com"

ENV         RUSTUP_HOME=/usr/local/rustup \
            CARGO_HOME=/usr/local/cargo \
            PATH=/usr/local/cargo/bin:$PATH

RUN         apt-get update \
                && apt-get -y install --no-install-recommends git dnsutils curl iproute2 ffmpeg tini pkg-config ca-certificates gcc libc6-dev \
                && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.56.0 --profile minimal \
                && apt-get clean && rm -rf /var/lib/apt/lists/* \
                && useradd -m -d /home/container container

USER        container
ENV         USER=container HOME=/home/container CARGO_HOME=/home/container/.cargo
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
