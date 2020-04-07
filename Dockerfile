FROM golang:1.13.4-buster
ARG MAKEARG
ARG MIRROR=original
ARG RUSTUP_UPDATE_ROOT
ARG RUSTUP_DIST_SERVER

MAINTAINER ldoublewood <ldoublewood@gmail.com>

ENV SRC_DIR /lotus

COPY docker/$MIRROR/sources.list /etc/apt/sources.list

RUN apt-get update && apt-get install -y ca-certificates llvm clang mesa-opencl-icd ocl-icd-opencl-dev

#using RUSTUP_UPDATE_ROOT and RUSTUP_DIST_SERVER
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y

# Get su-exec, a very minimal tool for dropping privileges,
# and tini, a very minimal init daemon for containers
#ENV SUEXEC_VERSION v0.2
#ENV TINI_VERSION v0.18.0
#RUN set -x \
#  && cd /tmp \
#  && git clone https://github.com/ncopa/su-exec.git \
#  && cd su-exec \
#  && git checkout -q $SUEXEC_VERSION \
#  && make \
#  && cd /tmp \
#  && wget -q -O tini https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini \
#  && chmod +x tini

# Download packages first so they can be cached.
COPY go.mod go.sum $SRC_DIR/
COPY extern/ $SRC_DIR/extern/
RUN bash -c 'if [ "$MIRROR" == "china" ]; then go env -w GOPROXY=https://goproxy.cn,direct && go env -w GOSUMDB="sum.golang.google.cn"; fi'

RUN cd $SRC_DIR \
  && go mod download

COPY Makefile $SRC_DIR

# Because extern/filecoin-ffi building script need to get version number from git
COPY .git/ $SRC_DIR/.git/
COPY .gitmodules $SRC_DIR/

COPY docker/$MIRROR/cargo_config $HOME/.cargo/config

# Download dependence first
RUN cd $SRC_DIR \
  && mkdir $SRC_DIR/build \
  && . $HOME/.cargo/env \
  && make deps

# Build the thing.
RUN cd $SRC_DIR \
  && . $HOME/.cargo/env \
  && make build/.filecoin-install

COPY . $SRC_DIR

# Build the thing.
RUN cd $SRC_DIR \
  && . $HOME/.cargo/env \
  && make $MAKEARG

# Now comes the actual target image, which aims to be as small as possible.
FROM busybox:1-glibc
MAINTAINER ldoublewood <ldoublewood@gmail.com>

# Get the executable binary and TLS CAs from the build container.
ENV SRC_DIR /lotus
COPY --from=0 $SRC_DIR/lotus /usr/local/bin/lotus
COPY --from=0 $SRC_DIR/lotus-storage-miner /usr/local/bin/lotus-storage-miner
COPY --from=0 $SRC_DIR/lotus-seed /usr/local/bin/lotus-seed
#COPY --from=0 $SRC_DIR/lotus-helper /usr/local/bin/helper
COPY --from=0 /etc/ssl/certs /etc/ssl/certs


# This shared lib (part of glibc) doesn't seem to be included with busybox.
COPY --from=0 /lib/x86_64-linux-gnu/libdl-2.28.so /lib/libdl.so.2
COPY --from=0 /lib/x86_64-linux-gnu/libutil-2.28.so /lib/libutil.so.1 
COPY --from=0 /usr/lib/x86_64-linux-gnu/libOpenCL.so.1.0.0 /lib/libOpenCL.so.1
COPY --from=0 /lib/x86_64-linux-gnu/librt-2.28.so /lib/librt.so.1
COPY --from=0 /lib/x86_64-linux-gnu/libgcc_s.so.1 /lib/libgcc_s.so.1

#COPY docker/script /script

# WS port
EXPOSE 1234
# P2P port
EXPOSE 5678


# Create the home directory and switch to a non-privileged user.
ENV HOME_PATH /data
ENV PARAMCACHE_PATH /var/tmp/filecoin-proof-parameters

RUN mkdir -p $HOME_PATH \
  && adduser -D -h $HOME_PATH -u 1000 -G users lotus \
  && chown lotus:users $HOME_PATH


VOLUME $HOME_PATH
VOLUME $PARAMCACHE_PATH

# Execute the daemon subcommand by default
CMD ["lotus", "daemon"]

