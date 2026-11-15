#!/usr/bin/env bash
# Build the ESP32-S31 toolchains inside Docker.
#
#   ./build.sh cross          # host -> riscv32 cross compiler
#   ./build.sh native         # riscv32 -> riscv32 GCC, static, runs on the board [needs cross]
#   ./build.sh make           # static GNU make for the board            [needs cross]
#   ./build.sh cc ARGS...     # run the cross gcc on files in this repo, e.g.
#                             #   ./build.sh cc -O2 -static examples/bench.c -o out/bench
#   ./build.sh shell          # interactive shell in the build container
#
# Toolchains are installed in a Docker volume (/build/out): the Linux headers
# need a case-sensitive filesystem, which macOS bind mounts are not.
# Release tarballs land in ./out.
set -euo pipefail

MCM_REPO=https://github.com/richfelker/musl-cross-make.git
MCM_REV=5e8042e63de29f8473fc3b0b831a587ba284e1a8
IMAGE=esp32s31-gcc-builder
TRIPLE=riscv32-linux-musl
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=${1:-cross}; shift || true
# Optimisation level used to build the native GCC itself (not what it emits).
# -Os makes cc1 smaller, which matters with ~4 MB of RAM for user space.
NATIVE_OPT=${NATIVE_OPT:--O2}

mkdir -p "$HERE/out" "$HERE/logs"
docker build -q -t "$IMAGE" "$HERE" >/dev/null

run() {
  docker run --rm ${TTY:-} \
    -v esp32s31-gcc-sources:/sources \
    -v esp32s31-gcc-build:/build \
    -v "$HERE:/src" -w /src \
    -e JOBS="$JOBS" -e MCM_REPO="$MCM_REPO" -e MCM_REV="$MCM_REV" -e TRIPLE="$TRIPLE" -e NATIVE_OPT="$NATIVE_OPT" \
    "$IMAGE" bash -c "$1"
}

PREP='set -euo pipefail
if [ ! -d /build/mcm/.git ]; then git clone -q "$MCM_REPO" /build/mcm; fi
cd /build/mcm && git fetch -q origin && git checkout -q "$MCM_REV"
mkdir -p /sources && rm -rf sources && ln -s /sources sources
cp /src/config/common.mak config.mak'

case "$STAGE" in
  cross)
    run "$PREP
      echo 'GCC_CONFIG += --enable-languages=c,c++' >> config.mak
      echo 'OUTPUT = /build/out/cross' >> config.mak
      time make -j\$JOBS
      rm -rf /build/out/cross && make install
      /build/out/cross/bin/\$TRIPLE-gcc --version | head -1
      tar -C /build/out -cJf /src/out/\$TRIPLE-cross-\$(uname -m).tar.xz cross
      ls -la /src/out" \
      2>&1 | tee "$HERE/logs/cross.log"
    ;;
  native)
    run "$PREP
      export PATH=/build/out/cross/bin:\$PATH
      cat /src/config/native.mak >> config.mak
      echo \"COMMON_CONFIG += CFLAGS='\$NATIVE_OPT -g0' CXXFLAGS='\$NATIVE_OPT -g0'\" >> config.mak
      SUF=\$( [ \"\$NATIVE_OPT\" = -O2 ] && echo || echo \"\$NATIVE_OPT\" )
      echo \"OUTPUT = /build/out/native\$SUF\" >> config.mak
      time make -j\$JOBS NATIVE=1 BUILD_DIR=build/native\$SUF/\$TRIPLE
      rm -rf /build/out/native\$SUF && make NATIVE=1 BUILD_DIR=build/native\$SUF/\$TRIPLE install
      file /build/out/native\$SUF/bin/gcc
      du -sh /build/out/native\$SUF /build/out/native\$SUF/libexec/gcc/*/*/cc1
      tar -C /build/out -cJf /src/out/\$TRIPLE-native-gcc\$SUF.tar.xz native\$SUF
      # gzip too: unpacking xz on the board takes >15 min, gzip about 2 min
      tar -C /build/out -czf /src/out/\$TRIPLE-native-gcc\$SUF.tar.gz native\$SUF
      ls -la /src/out" \
      2>&1 | tee "$HERE/logs/native.log"
    ;;
  make)
    # Static GNU make for the board (Buildroot's image has none).
    # -std=gnu17: make 4.4.1 declares getenv() K&R-style, which C23 (GCC 15's default) rejects.
    run "set -euo pipefail
      export PATH=/build/out/cross/bin:\$PATH
      cd /tmp && curl -fsSL https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz | tar xz && cd make-4.4.1
      ./configure -q --host=\$TRIPLE --disable-nls LDFLAGS='-static -s' CFLAGS='-O2 -std=gnu17'
      make -s -j\$JOBS && cp make /src/out/make && file /src/out/make" \
      2>&1 | tee "$HERE/logs/make.log"
    ;;
  cc)
    run "/build/out/cross/bin/\$TRIPLE-gcc $(printf '%q ' "$@")"
    ;;
  shell)
    TTY=-it run "$PREP; export PATH=/build/out/cross/bin:\$PATH; exec bash"
    ;;
  *)
    echo "usage: $0 cross|native|make|cc ARGS|shell" >&2; exit 2 ;;
esac
