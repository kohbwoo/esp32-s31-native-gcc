# Results (2026-11-15)

Board: ESP32-S31-Function-CoreBoard-1, RV32IMAC @ 320 MHz, ~11 MB RAM for Linux, root on a USB 2.0 stick.
Linux: esp32-s31-linux v0.11.0 (`coreboard1`). Toolchain: GCC 15.1.0, binutils 2.44, musl 1.2.6.
Raw board logs: [results/](results/).

## Building the toolchain (Apple M4 Pro, Docker)

| Stage | Time |
|---|---|
| Cross toolchain (C, C++) | 3 min 16 s |
| Native GCC (C, static) | 3 min 2 s |

## Compiling on the board

| What | Settings | Time |
|---|---|---|
| hello.c, `-O2 -static` | default | 65–69 s |
| hello.c, `-O2 -static` | `lowmem.sh` | 21 s |
| core_util.c (249 lines) | default | 760 s |
| core_util.c | cc1 built with `-Os` | 1033 s |
| core_util.c | `lowmem.sh` | 124 s |
| CoreMark, 6 files + link | `lowmem.sh` | 886 s (14 min 46 s) |
| Lua 5.4.9, 33 files + link | `lowmem.sh` | 18 205 s (5 h 3 min) |

Even hello.c is slow because cc1 is 45 MB, four times the RAM, and gets paged in from the USB stick
on every run: the CPU is busy only 12–18 % of the time. `lowmem.sh` frees memory so fewer pages are
evicted and read back, which cuts the page faults to about a third.

## CoreMark 1.0 (`-O2`)

| Binary | Score |
|---|---|
| cross-compiled on the Mac, services running | 934.42 |
| cross-compiled on the Mac, services stopped | 970.87 |
| **compiled on the board**, services stopped | **971.56** |
| Mac M4 Pro, one core (Apple clang) | 47 626.61 |

## Lua 5.4.9

Same flags as `make linux`. The board takes 5 h 3 min; the Mac takes 2.9 s with the same GCC.
Slowest files: lvm.c 2125 s, lapi.c 1562 s, lstrlib.c 1365 s. The big files need more than the
~6 MB free, so cc1 also swaps.

The board-built `lua` (693 KB, static) runs `sum 1..1e6` in 309 ms (MicroPython: 10 851 ms, C: 44 ms)
and recursive `fib(25)` in 221 ms.

## Release check

The release tarball, installed on a fresh board by following the README, takes 2 min 51 s
including download and checksums, and produces a hello binary byte-identical to the dev build's.
