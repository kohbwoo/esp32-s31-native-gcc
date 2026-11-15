#!/bin/sh
# Runs ON the ESP32-S31: build CoreMark with the native GCC, one file at a time,
# then run it. Run lowmem.sh first. Log: /root/coremark-build.log
export PATH=/opt/gcc/bin:$PATH TMPDIR=/root/tmp
mkdir -p "$TMPDIR"
cd /root/coremark || exit 1
F="-O2"
T0=$(date +%s)
(
  set -e
  echo "== native CoreMark build: gcc $(gcc -dumpversion) $F, $(free -m | awk '/Mem/{print $7}') MB available"
  for c in core_list_join.c core_main.c core_matrix.c core_state.c core_util.c posix/core_portme.c; do
    S=$(date +%s)
    gcc $F -Iposix -I. -DFLAGS_STR="\"$F (native, on ESP32-S31)\"" -DPERFORMANCE_RUN=1 -DITERATIONS=0 \
        -c "$c" -o "$TMPDIR/$(basename "$c" .c).o"
    echo "$(( $(date +%s) - S ))s  $c"
  done
  S=$(date +%s)
  gcc -static -o /root/coremark-native "$TMPDIR"/core_*.o -lrt
  echo "$(( $(date +%s) - S ))s  link"
  echo "== total $(( $(date +%s) - T0 ))s"
  /root/coremark-native
) > /root/coremark-build.log 2>&1
echo "rc=$? total=$(( $(date +%s) - T0 ))s" >> /root/coremark-build.log
sync
