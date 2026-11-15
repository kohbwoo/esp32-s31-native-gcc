#!/usr/bin/env bash
# Collect release assets in out/release: board binaries, lowmem.sh, checksums,
# and the exact upstream source tarballs they were built from (GPL compliance).
set -euo pipefail
cd "$(dirname "$0")/.."
R=out/release; rm -rf "$R"; mkdir -p "$R/sources"
cp out/riscv32-linux-musl-native-gcc.tar.gz out/riscv32-linux-musl-native-gcc.tar.xz \
   out/riscv32-linux-musl-cross-aarch64.tar.xz out/make examples/lowmem.sh "$R/"
docker run --rm -v esp32s31-gcc-sources:/s -v "$PWD/$R/sources:/o" esp32s31-gcc-builder \
  bash -c 'cp /s/* /o/ && cd /o && curl -fsSLO https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz'
(cd "$R" && shasum -a 256 *.* make sources/* > SHA256SUMS)
du -sh "$R"/* | sort -h
