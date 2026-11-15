#!/usr/bin/env python3
"""Talk to the ESP32-S31 Linux shell over the UART console.

  board.py [-p PORT] run "cmd" [...]        run shell commands, print output
  board.py [-p PORT] push LOCAL REMOTE      copy a file (base64 over the console)

The board must be at a shell prompt. Opening the port can reset some boards;
we wait for a prompt before sending anything.
"""
import argparse
import os
import base64
import hashlib
import re
import sys
import time

import serial

PROMPT = re.compile(rb"root@[\w-]+:[^#\n]*# *$")


def open_port(port):
    s = serial.Serial()
    s.port, s.baudrate, s.timeout = port, 115200, 0.1
    # Leave DTR and RTS both asserted (what macOS does on open). The board's
    # auto-reset circuit resets it when RTS is asserted with DTR released, so
    # releasing them one by one after open used to reboot the board.
    s.dtr = s.rts = True
    s.open()
    return s


def read_until_prompt(s, timeout, echo=True):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        d = s.read(4096)
        if d:
            buf.extend(d)
            if echo:
                sys.stdout.write(d.decode("utf-8", "replace").replace("\r", ""))
                sys.stdout.flush()
            if PROMPT.search(bytes(buf[-200:])):
                return bytes(buf)
    raise TimeoutError("no shell prompt from the board")


INTERRUPT = False  # --interrupt: send Ctrl-C first (kills a running command)


def sync_prompt(s, timeout=40):
    s.reset_input_buffer()
    s.write(b"\x03\r\n" if INTERRUPT else b"\r\n")
    return read_until_prompt(s, timeout, echo=False)


def cmd_run(s, cmds, timeout):
    sync_prompt(s)
    for c in cmds:
        s.write(c.encode() + b"\r\n")
        read_until_prompt(s, timeout)
    print()


def wait_ps2(s, timeout=5):
    buf = bytearray()
    end = time.time() + timeout
    while time.time() < end:
        d = s.read(256)
        if d:
            buf.extend(d)
            if buf.endswith(b"> "):
                return
    raise TimeoutError(f"no '> ' prompt, got {bytes(buf[-80:])!r}")


def cmd_push(s, local, remote):
    data = open(local, "rb").read()
    md5 = hashlib.md5(data).hexdigest()
    lines = base64.encodebytes(data).decode().splitlines()
    sync_prompt(s)
    # One line at a time, waiting for the shell's "> " continuation prompt:
    # streaming at full 115200 overruns the board's console input.
    s.write(b"base64 -d > '%s' <<'__B64__'\r" % remote.encode())
    wait_ps2(s)
    t0 = time.time()
    for i, line in enumerate(lines):
        s.write(line.encode() + b"\r")
        wait_ps2(s)
        if i % 32 == 31 or i == len(lines) - 1:
            pct = 100 * (i + 1) // len(lines)
            sys.stderr.write(f"\r{pct:3d}%  {len(data)} bytes")
    s.write(b"__B64__\r")
    read_until_prompt(s, 30, echo=False)
    s.write(b"md5sum '%s'\r" % remote.encode())
    out = read_until_prompt(s, 60, echo=False).decode("utf-8", "replace")[-300:]
    dt = time.time() - t0
    sys.stderr.write(f"\r100%  {len(data)} bytes in {dt:.1f}s\n")
    if md5 in out:
        print(f"ok  {remote}  md5 {md5}")
    else:
        print(f"MD5 MISMATCH: local {md5}\nboard said:\n{out}")
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default=os.environ.get("BOARD_PORT", "/dev/cu.usbserial-21430"))
    ap.add_argument("-t", "--timeout", type=float, default=120)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run"); r.add_argument("cmds", nargs="+")
    p = sub.add_parser("push"); p.add_argument("local"); p.add_argument("remote")
    ap.add_argument("--interrupt", action="store_true")
    a = ap.parse_args()
    global INTERRUPT
    INTERRUPT = a.interrupt
    s = open_port(a.port)
    try:
        if a.cmd == "run":
            cmd_run(s, a.cmds, a.timeout)
        else:
            cmd_push(s, a.local, a.remote)
    finally:
        s.close()


if __name__ == "__main__":
    main()
