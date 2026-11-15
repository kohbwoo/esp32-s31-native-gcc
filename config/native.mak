# Extra settings for the native (runs on the ESP32-S31) toolchain.
# Static and stripped: the board's rootfs has its own musl, and we don't want
# to depend on its exact version or dynamic-linker name.
COMMON_CONFIG += LDFLAGS="-static -s"

# The board only needs a C compiler (C++ would need far more RAM to run).
GCC_CONFIG += --enable-languages=c
# musl-cross-make installs the headers in <prefix>/include, not <prefix>/usr/include.
# (The first build needed `ln -s . /opt/gcc/usr` on the board instead.)
GCC_CONFIG += --with-native-system-header-dir=/include
# ...and at build time those headers live in the cross toolchain's sysroot
# (otherwise fixincludes looks for //include on the build machine and fails).
GCC_CONFIG += --with-build-sysroot=/build/out/cross/riscv32-linux-musl

# musl >= 1.2.5 declares basename() only in <libgen.h>; GCC's configure then
# thinks it is missing and libiberty.h adds a conflicting C++ declaration.
# GCC itself only uses lbasename(), so tell configure it is declared.
# GCC's top-level configure does not pass VAR=value on to libcpp/gcc, so these
# go through the environment (autoconf reads ac_cv_* from it).
export ac_cv_have_decl_basename = yes
export ac_cv_have_decl_basename_char_p_ = yes
