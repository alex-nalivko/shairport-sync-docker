FROM ubuntu:21.10 AS builder-base

ENV DEBIAN_FRONTEND=noninteractive 

# General Build System:
RUN apt update && apt install -y \
        build-essential \
        libpopt-dev \
        libasound2-dev \
        avahi-daemon \
        libavahi-client-dev \
        libssl-dev \
        libsoxr-dev \
        libavcodec-dev \
        libavformat-dev \
        uuid-dev \
        libgcrypt-dev \
        git \
        autoconf \
        automake \
        libtool \
        dbus \
        libdaemon-dev \
        libconfig-dev \
        libsndfile-dev \
        mosquitto-dev \
        xmltoman \
        libplist-dev \
        libsodium-dev \
        libgcrypt-dev \
        libavutil-dev \
        libmbedtls-dev \
        libglib2.0-dev \
        libmosquitto-dev \
        xxd

# ALAC Build System:
FROM builder-base AS builder-alac

RUN     git clone https://github.com/mikebrady/alac
WORKDIR alac
RUN     autoreconf -fi
RUN     ./configure
RUN     make
RUN     make install


# NQPTP Time sync:
FROM builder-base AS builder-nqptp

RUN     git clone https://github.com/mikebrady/nqptp.git
WORKDIR nqptp
RUN     autoreconf -fi
RUN     ./configure
RUN     make
RUN     make install

# Shairport Sync Build System:
FROM    builder-base AS builder-sps

# This may be modified by the Github Action Workflow.
ARG SHAIRPORT_SYNC_BRANCH=master

COPY    --from=builder-alac /usr/local/lib/libalac.* /usr/local/lib/
COPY    --from=builder-alac /usr/local/lib/pkgconfig/alac.pc /usr/local/lib/pkgconfig/alac.pc
COPY    --from=builder-alac /usr/local/include /usr/local/include

RUN     git clone https://github.com/mikebrady/shairport-sync
WORKDIR shairport-sync
RUN     git checkout "development"
RUN     autoreconf -fi
RUN     ./configure \
              --with-airplay-2 \
              --with-alsa \
              --with-avahi \
              --with-ssl=openssl \
              --with-soxr \
              --sysconfdir=/etc \
              --with-apple-alac
RUN     make -j $(nproc)
RUN     make install

# Shairport Sync Runtime System:
FROM    alpine:3.15

RUN     apk -U add \
              alsa-lib \
              dbus \
              popt \
              glib \
              mbedtls \
              soxr \
              avahi \
              libconfig \
              libsndfile \
              mosquitto-libs \
              su-exec \
              libgcc \
              libgc++

RUN     rm -rf  /lib/apk/db/*

COPY    --from=builder-nqptp /usr/local/bin/nqptp /usr/local/bin/
COPY    --from=builder-alac /usr/local/lib/libalac.* /usr/local/lib/
COPY    --from=builder-sps /etc/shairport-sync* /etc/
COPY    --from=builder-sps /usr/local/bin/shairport-sync /usr/local/bin/shairport-sync

# Create non-root user for running the container -- running as the user 'shairport-sync' also allows
# Shairport Sync to provide the D-Bus and MPRIS interfaces within the container

RUN 	addgroup shairport-sync 
RUN 	adduser -D shairport-sync -G shairport-sync

# Add the shairport-sync user to the pre-existing audio group, which has ID 29, for access to the ALSA stuff
RUN 	addgroup -g 29 docker_audio && addgroup shairport-sync docker_audio

COPY 	start.sh /

ENTRYPOINT [ "/start.sh" ]

