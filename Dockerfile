# Build environment for the ESP32-S31 (RV32IMAC, ilp32, musl) GCC toolchains.
# Runs natively on arm64 (Apple Silicon) and x86_64 hosts.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bison flex texinfo gawk file \
        ca-certificates wget curl git rsync patch \
        xz-utils bzip2 gzip unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
