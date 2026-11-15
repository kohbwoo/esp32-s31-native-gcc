#!/bin/sh
# Runs ON the ESP32-S31: build Lua 5.4.9 with the native GCC, one file at a time
# (same flags as `make linux`), then link a static lua and run a quick benchmark.
# Run lowmem.sh first. Sources must already be in /root/lua-5.4.9.
# Log: /root/lua-build.log. Re-running resumes: finished .o files are kept
# (pass "clean" to start over).
export PATH=/opt/gcc/bin:$PATH TMPDIR=/root/tmp
mkdir -p "$TMPDIR"
cd /root/lua-5.4.9/src || exit 1
[ "$1" = clean ] && rm -f ./*.o liblua.a lua
F="-std=gnu99 -O2 -Wall -Wextra -DLUA_COMPAT_5_3 -DLUA_USE_LINUX"
CORE="lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio"
LIB="lauxlib lbaselib lcorolib ldblib liolib lmathlib loadlib loslib lstrlib ltablib lutf8lib linit"
T0=$(date +%s)
(
  set -e
  echo "== native Lua build: gcc $(gcc -dumpversion) $F, $(free -m | awk '/Mem/{print $7}') MB available"
  for f in $CORE $LIB lua; do
    if [ -s "$f.o" ]; then echo "skip  $f.c"; continue; fi
    S=$(date +%s)
    gcc $F -c "$f.c" -o "$f.o.tmp" && mv "$f.o.tmp" "$f.o"
    echo "$(( $(date +%s) - S ))s  $f.c"
    sync
  done
  S=$(date +%s)
  ar rcs liblua.a $(for f in $CORE $LIB; do echo "$f.o"; done)
  gcc -static -o lua lua.o liblua.a -lm
  echo "$(( $(date +%s) - S ))s  link"
  echo "== total $(( $(date +%s) - T0 ))s"
  ls -l lua
  ./lua -v
  ./lua -e 'local t=os.clock(); local s=0; for i=1,1000000 do s=s+i end; print("lua sum 1e6", s, string.format("%.0f ms", (os.clock()-t)*1000))'
  ./lua -e 'local function fib(n) if n<2 then return n end return fib(n-1)+fib(n-2) end; local t=os.clock(); print("lua fib(25)", fib(25), string.format("%.0f ms", (os.clock()-t)*1000))'
) > /root/lua-build.log 2>&1
echo "rc=$? total=$(( $(date +%s) - T0 ))s" >> /root/lua-build.log
sync
