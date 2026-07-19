# syntax=docker/dockerfile:1
#
# cod2-docker - Call of Duty 2 dedicated server (Debian 13 default, Ubuntu 24.04 via BASE_IMAGE)
#
# Stages:
#   speex          32-bit Speex build (voice chat support for zk_libcod)
#   libcod-builder zk_libcod build environment; also usable standalone to
#                  compile any libcod repo/branch/flags without an image rebuild
#   runtime        the actual server image (default target)

# Base OS: any zk_libcod-supported platform (debian:13-slim, ubuntu:24.04)
ARG BASE_IMAGE="debian:13-slim"
ARG LIBCOD_REPO="https://github.com/ibuddieat/zk_libcod"
ARG LIBCOD_REF="master"
# doit.sh positional args; always include one of: mysql1 | mysql2 | nomysql
ARG LIBCOD_BUILD_ARGS="mysql1"
ARG SPEEX_VERSION="Speex-1.2.1"
ARG WITH_FFMPEG=0

# ==================================================================
# Stage: speex - 32-bit Speex shared library
# ==================================================================
FROM --platform=linux/amd64 ${BASE_IMAGE} AS speex
ARG SPEEX_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git build-essential gcc-multilib \
      automake autoconf libtool pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Xiph's own gitlab first; their official GitHub mirror as fallback
# (gitlab.xiph.org sits behind Anubis and is sometimes unreachable)
RUN git clone --depth 1 --branch "${SPEEX_VERSION}" https://gitlab.xiph.org/xiph/speex.git /tmp/speex \
    || git clone --depth 1 --branch "${SPEEX_VERSION}" https://github.com/xiph/speex.git /tmp/speex \
    && cd /tmp/speex \
    && env AUTOMAKE=automake ACLOCAL=aclocal LIBTOOLIZE=libtoolize ./autogen.sh >/dev/null \
    && ./configure \
         CFLAGS="-m32 -O2" \
         CXXFLAGS="-m32 -O2" \
         LDFLAGS=-m32 \
         --build=x86_64-pc-linux-gnu \
         --host=i686-pc-linux-gnu \
         >/dev/null \
    && sed -i 's/u_int\([0-9]*\)_t/uint\1_t/g' include/speex/speex_config_types.h \
    && make >/dev/null \
    && make install >/dev/null \
    && rm -rf /tmp/speex

# ==================================================================
# Stage: libcod-builder - compile zk_libcod (image build AND on demand)
# ==================================================================
FROM --platform=linux/amd64 ${BASE_IMAGE} AS libcod-builder
ARG LIBCOD_REPO
ARG LIBCOD_REF
ARG LIBCOD_BUILD_ARGS

RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git g++-multilib \
      default-libmysqlclient-dev:i386 \
    && rm -rf /var/lib/apt/lists/*

# 32-bit speex library + headers so libcod can link -lspeex
COPY --from=speex /usr/local/lib/libspeex* /usr/local/lib/
COPY --from=speex /usr/local/include/speex /usr/local/include/speex
RUN ldconfig
ENV LIBRARY_PATH=/usr/local/lib

COPY docker/build-libcod-inner.sh /usr/local/bin/build-libcod-inner.sh
RUN chmod +x /usr/local/bin/build-libcod-inner.sh

# Bake the default libcod at image build time
RUN LIBCOD_REPO="${LIBCOD_REPO}" LIBCOD_REF="${LIBCOD_REF}" OUT_DIR=/baked \
      build-libcod-inner.sh ${LIBCOD_BUILD_ARGS}

# Standalone use: mount ./libcod at /out; flags come from positional args
# or the LIBCOD_BUILD_ARGS env var (no default CMD so env can win)
ENV OUT_DIR=/out
ENTRYPOINT ["/usr/local/bin/build-libcod-inner.sh"]

# ==================================================================
# Stage: runtime - the server image (default target)
# ==================================================================
FROM --platform=linux/amd64 ${BASE_IMAGE} AS runtime
ARG WITH_FFMPEG

# mysql client runtime: Debian ships libmariadb3:i386, Ubuntu libmysqlclient21:i386
RUN dpkg --add-architecture i386 \
    && apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget netcat-openbsd util-linux unzip jq \
      libstdc++6:i386 \
    && { apt-get install -y --no-install-recommends libmariadb3:i386 || true; } \
    && { apt-get install -y --no-install-recommends libmysqlclient21:i386 || true; } \
    && ls /usr/lib/i386-linux-gnu/ | grep -qE 'libmariadb|libmysqlclient' \
    && rm -rf /var/lib/apt/lists/* \
    # libstdc++5 is no longer packaged on Debian 13 / Ubuntu 24.04, required by cod2_lnxded
    && wget -q http://ftp.debian.org/debian/pool/main/g/gcc-3.3/libstdc++5_3.3.6-32_i386.deb -O /tmp/libstdc++5.deb \
    && echo "ea5232f02e708ec1876d5539ac95b6407aea08954f5914aa548df5c66fa62294  /tmp/libstdc++5.deb" | sha256sum -c - \
    && dpkg -i /tmp/libstdc++5.deb \
    && rm /tmp/libstdc++5.deb

# Optional ffmpeg (zk_libcod getSoundDuration); adds ~300 MB
RUN if [ "${WITH_FFMPEG}" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends ffmpeg \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# 32-bit runtime libs always present so ANY libcod2.so (speex/mysql or not)
# loads without an image change
COPY --from=speex /usr/local/lib/libspeex*.so* /usr/lib/i386-linux-gnu/
RUN ldconfig

# mysql client compat symlink: Debian ships only mariadb, but libcod links
# -lmysqlclient. Never clobber a real libmysqlclient (Ubuntu ships one).
RUN if [ -e /usr/lib/i386-linux-gnu/libmariadb.so.3 ] \
       && [ ! -e /usr/lib/i386-linux-gnu/libmysqlclient.so.21 ]; then \
      ln -s libmariadb.so.3 /usr/lib/i386-linux-gnu/libmysqlclient.so.21; \
    fi \
    && ldconfig

RUN useradd -m -d /server -s /bin/bash cod2

COPY --chmod=0755 bin/cod2_lnxded_* /server/bin/
COPY --from=libcod-builder /baked/libcod2.so /server/libcod/libcod2.so.default
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN mkdir -p /server/game /server/libcod/custom /server/libcod/fetched \
    && chown -R cod2:cod2 /server

EXPOSE 28960/udp
VOLUME ["/server/game"]
WORKDIR /server

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
