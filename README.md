# ESP32-S31 native GCC: compiling C on the ESP32 itself

**GCC 15.1 running on an ESP32 microcontroller.** This is a native, self-hosted C compiler
(GCC 15.1, binutils 2.44, musl 1.2.6) for the RISC-V **ESP32-S31 running Linux with an MMU**.
No PC is involved: the board compiles and links C programs by itself, including CoreMark and
all of Lua 5.4.

Prebuilt binaries are on the [Releases](../../releases) page. The Docker scripts here rebuild them from source.

```
root@esp32s31:~# gcc -v 2>&1 | tail -1
gcc version 15.1.0 (GCC)
root@esp32s31:~# ./lua -v
Lua 5.4.9  Copyright (C) 1994-2026 Lua.org, PUC-Rio      <- built on the board, 5 h 3 min
```

| | |
|---|---|
| Board | ESP32-S31-Function-CoreBoard-1 (ESP32-S31-WROOM-3-N16R16V) |
| CPU | RISC-V RV32IMAC (+Zba/Zbb/Zbs), 320 MHz, one core used by Linux, Sv32 MMU |
| Memory | 16 MB PSRAM, about 11 MB left for Linux, about 6 MB free for the compiler |
| Storage | root file system on a USB 2.0 stick (also used for swap) |
| OS | [annoyedmilk/esp32-s31-linux](https://github.com/annoyedmilk/esp32-s31-linux) v0.11.0 (`coreboard1` build, Linux 7.3.1, Buildroot) |

## Results

Full numbers are in [RESULTS.md](RESULTS.md). The raw board logs are in [results/](results/).

**CoreMark 1.0** (GCC 15.1 `-O2`, services stopped):

| Binary | Score |
|---|---|
| cross-compiled on a Mac | 970.87 |
| **compiled on the ESP32-S31 itself** | **971.56** |
| for scale: Apple M4 Pro, one core | 47 626.61 |

The board-built binary scores the same as the cross-built one, so the native compiler
generates the same code. That works out to about 3.0 CoreMark/MHz.

**Compile times on the board:**

| What | Time |
|---|---|
| hello.c | 21 s with `lowmem.sh`, ~65 s without |
| CoreMark (6 files + link) | 14 min 46 s |
| Lua 5.4.9 (33 files + link, `-O2`) | 5 h 3 min (2.9 s on the Mac with the same GCC) |

## Quick start: install GCC on the ESP32-S31

You need the board running esp32-s31-linux with a USB-stick root file system
(about 300 MB free: 192 MB unpacked plus the tarball), and a way to copy files to it (Wi-Fi + `curl`, or the stick itself).

From the [Releases](../../releases) page, get `riscv32-linux-musl-native-gcc.tar.gz`, `make` and `lowmem.sh`.
Then, on the board:

```sh
gzip -dc riscv32-linux-musl-native-gcc.tar.gz | tar x -C /opt   # BusyBox tar has no -z
mv /opt/native /opt/gcc
cp make /opt/gcc/bin/ && chmod +x /opt/gcc/bin/make
export PATH=/opt/gcc/bin:$PATH

sh lowmem.sh            # strongly recommended, see below
printf '#include <stdio.h>\nint main(){puts("hello from gcc on esp32");}\n' > hello.c
TMPDIR=/root/tmp gcc -O2 -static hello.c -o hello && ./hello
```

Use the `.tar.gz` instead of the `.tar.xz`: unpacking xz on the board takes more than 15 minutes,
gzip about 2. On a fresh board the whole install (download, checksum, unpack) took 2 min 51 s.

## Build the toolchain yourself (Docker)

You need Docker, about 10 GB of disk space, and roughly 7 minutes on an Apple M4 Pro.

```sh
./build.sh cross     # host -> riscv32 cross compiler (C and C++), ~3 min
./build.sh native    # riscv32 GCC that runs on the board (C only, static), ~3 min
./build.sh make      # static GNU make for the board
ls out/              # release tarballs
```

Everything is pinned: [musl-cross-make](https://github.com/richfelker/musl-cross-make)
at commit `5e8042e`, plus [config/common.mak](config/common.mak) and [config/native.mak](config/native.mak).
The toolchains are installed in a Docker volume, because the Linux headers need a case-sensitive
file system and macOS bind mounts are not case-sensitive.

There is also a helper that runs the cross compiler on files in this repo:

```sh
./build.sh cc -O2 -static examples/bench.c -o out/bench
```

## Making compiles 6x faster: `lowmem.sh`

With the stock image, compiling a 250-line file took **760 s**. With
[examples/lowmem.sh](examples/lowmem.sh) it takes **124 s**. The script does four things:

- stops Wi-Fi, BLE, mDNS, cron, dropbear and syslog;
- turns off zram: compressing pages costs CPU that the single core needs;
- sets `vm.page-cluster=0`, so the kernel reads one page at a time instead of 8;
- drops the page cache and creates `/root/tmp`. The build scripts then set `TMPDIR=/root/tmp`, so temp files go to the USB stick instead of the 2 MB tmpfs.

Together these raise free RAM from 3.5 MB to 5.8 MB. The compiler is memory-bound, not
CPU-bound: building the bigger Lua files still swapped, with about 38 % of the time spent
waiting for I/O.

Even hello.c takes 20–65 s: cc1 is 45 MB and is paged in from the USB stick on every run.

Things that did **not** help:
- **cc1 built with `-Os`** makes the binary smaller but compiles 36 % slower.
- **`make -j2`** isn't possible: the kernel runs one core. It would also double memory use.

## Pitfalls (and how this repo handles them)

| Problem | Fix |
|---|---|
| A C-only cross compiler makes the native GCC build pick up the host's `g++`, so you get aarch64 objects inside a riscv32 binary | build the cross compiler with `c,c++` |
| musl ≥ 1.2.5 `basename()` clashes with libiberty's declaration (`ambiguating new declaration`) | `export ac_cv_have_decl_basename_char_p_=yes` (the top-level `configure` doesn't pass `VAR=value` to libcpp) |
| `stdio.h: No such file` on the board: musl-cross-make installs the headers in `<prefix>/include` | `--with-native-system-header-dir=/include` plus `--with-build-sysroot` (otherwise fixincludes fails) |
| GNU make 4.4.1 doesn't build with GCC 15's C23 default (`char *getenv()`) | `CFLAGS=-std=gnu17` |
| `musl-cross-make` with an absolute `BUILD_DIR` fails with "No rule to make target Makefile" | use a relative path |
| Opening the serial port resets the board (auto-reset circuit) | keep DTR **and** RTS asserted ([tools/board.py](tools/board.py)) |
| Pasting base64 into the console at 115200 baud corrupts the data | wait for the `> ` prompt after every line |

## Repository layout

```
build.sh                  cross / native / make / cc / shell stages (Docker)
Dockerfile                Debian bookworm build image
config/                   musl-cross-make configuration
examples/lowmem.sh        free memory on the board before compiling
examples/build-*-on-board.sh   CoreMark and Lua builds with per-file timing
examples/bench.c          tiny C loop benchmark
examples/coremark/        EEMBC CoreMark (Apache 2.0, unmodified)
tools/board.py            run commands on and push files to the board over the UART console
RESULTS.md, results/      measurements and raw logs
```

## FAQ

**Can an ESP32 really compile its own code?** Yes, but only the ESP32-S31 running Linux. It has an
MMU, 16 MB of PSRAM and a USB host port for storage. Other ESP32 chips have no MMU and usually run
FreeRTOS, so they can't host GCC.

**Is it useful?** Not as a development setup: the Mac builds Lua in 2.9 s, the board in 5 hours.
It shows what this chip can do and gives the board a working C compiler for small programs.

**Does C++ work?** The native compiler is C only, to keep cc1 small. The cross compiler supports C and C++.

**Which target does it use?** `riscv32-linux-musl`, rv32imac / ilp32, static binaries.

## Licenses

- The scripts and configuration in this repository: MIT, © 2026 Byungwoo Koh, see [LICENSE](LICENSE).
- The release binaries contain GCC and binutils (GPL-3.0 with the GCC Runtime Library Exception),
  musl (MIT) and Linux UAPI headers (GPL-2.0 with the syscall note). They were built from
  unmodified upstream sources. The exact versions and the way to rebuild them are in this repo,
  and the source tarballs are attached to each release.
- This is an independent hobby project, not affiliated with or endorsed by Espressif Systems.
  ESP32 is a trademark of Espressif Systems.
- [examples/coremark](examples/coremark) is EEMBC CoreMark, Apache 2.0.
  "CoreMark" is a trademark of EEMBC. The scores above are informal measurements, not certified ones.

## Credits

- [annoyedmilk/esp32-s31-linux](https://github.com/annoyedmilk/esp32-s31-linux): the Linux port that makes this possible
- [musl-cross-make](https://github.com/richfelker/musl-cross-make) by Rich Felker
- GCC, binutils, musl, Lua, EEMBC CoreMark
