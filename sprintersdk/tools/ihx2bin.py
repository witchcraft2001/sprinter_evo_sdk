#!/usr/bin/env python3
"""Flatten an Intel HEX file into a raw binary (from its lowest address)."""

from __future__ import annotations

import sys
from pathlib import Path


def parse_ihx(path: Path) -> dict[int, int]:
    data: dict[int, int] = {}
    upper = 0
    for lineno, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise SystemExit(f"ihx2bin: {path}:{lineno}: bad record")
        raw = bytes.fromhex(line[1:])
        length, addr, rectype = raw[0], (raw[1] << 8) | raw[2], raw[3]
        if sum(raw) & 0xFF:
            raise SystemExit(f"ihx2bin: {path}:{lineno}: bad checksum")
        if rectype == 0x00:
            base = upper + addr
            for i, byte in enumerate(raw[4:4 + length]):
                data[base + i] = byte
        elif rectype == 0x01:
            break
        elif rectype == 0x04:
            upper = ((raw[4] << 8) | raw[5]) << 16
    return data


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        raise SystemExit("usage: ihx2bin.py <in.ihx> <out.bin>")
    data = parse_ihx(Path(argv[0]))
    if not data:
        raise SystemExit("ihx2bin: no data")
    lo, hi = min(data), max(data)
    out = bytearray(hi - lo + 1)
    for addr, byte in data.items():
        out[addr - lo] = byte
    Path(argv[1]).write_bytes(out)
    print(f"ihx2bin: {argv[1]} ({len(out)} bytes, org 0x{lo:04X})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
