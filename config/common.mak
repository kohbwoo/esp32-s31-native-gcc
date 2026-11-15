# Shared musl-cross-make settings for the ESP32-S31.
# The chip is RV32IMAC (no FPU used by Linux), so everything is soft-float ilp32.

TARGET       = riscv32-linux-musl
GCC_VER      = 15.1.0
BINUTILS_VER = 2.44
MUSL_VER     = 1.2.6
LINUX_VER    = 6.15.7

GCC_CONFIG += --with-arch=rv32imac --with-abi=ilp32
# --enable-languages is set per stage: the cross compiler needs C++ too,
# because GCC itself is C++ and the native build is compiled with it.
GCC_CONFIG += --disable-multilib --disable-libsanitizer --disable-libquadmath
COMMON_CONFIG += --disable-nls
COMMON_CONFIG += CFLAGS="-O2 -g0" CXXFLAGS="-O2 -g0"
