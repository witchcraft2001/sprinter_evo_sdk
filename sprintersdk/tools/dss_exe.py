#!/usr/bin/env python3
"""Create a Sprinter DSS EXE from Intel HEX, optionally appending assets."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


EXE_SIGNATURE = b"EXE"
EXE_VERSION = 1
EXE_HEADER_SIZE = 512
DSS_MIN_LOAD = 0x4100
# di(1) + ld hl,nn(3) + ld de,nn(3) + ld bc,nn(3) + ldir(2) + ld sp,nn(3) + jp nn(3)
LOW_COPY_LOADER_SIZE = 18


def parse_ihx(path: Path) -> dict[int, int]:
    data: dict[int, int] = {}
    upper = 0

    for lineno, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise SystemExit(f"dss_exe: {path}:{lineno}: bad Intel HEX record")

        raw = bytes.fromhex(line[1:])
        length = raw[0]
        addr = (raw[1] << 8) | raw[2]
        rectype = raw[3]
        payload = raw[4:4 + length]
        checksum = sum(raw) & 0xFF
        if checksum != 0:
            raise SystemExit(f"dss_exe: {path}:{lineno}: bad checksum")

        if rectype == 0x00:
            base = upper + addr
            for offset, byte in enumerate(payload):
                data[base + offset] = byte
        elif rectype == 0x01:
            break
        elif rectype == 0x04:
            if length != 2:
                raise SystemExit(f"dss_exe: {path}:{lineno}: bad extended linear address")
            upper = ((payload[0] << 8) | payload[1]) << 16
        else:
            # SDCC z80 output should not need other record types here.
            continue

    return data


def contiguous_image(data: dict[int, int], load: int) -> bytes:
    if not data:
        raise SystemExit("dss_exe: IHX contains no data")

    min_addr = min(data)
    max_addr = max(data)
    if min_addr < load:
        raise SystemExit(
            f"dss_exe: IHX has data at 0x{min_addr:04X}, below load address 0x{load:04X}"
        )

    out = bytearray(max_addr - load + 1)
    for addr, byte in data.items():
        out[addr - load] = byte
    return bytes(out)


def make_header(load: int, entry: int, stack: int, loader_size: int = 0) -> bytes:
    header = bytearray(EXE_HEADER_SIZE)
    header[0:3] = EXE_SIGNATURE
    header[3] = EXE_VERSION
    struct.pack_into("<I", header, 0x04, EXE_HEADER_SIZE)
    struct.pack_into("<H", header, 0x08, loader_size)
    struct.pack_into("<H", header, 0x0A, 0)
    struct.pack_into("<H", header, 0x0C, 0)
    struct.pack_into("<H", header, 0x0E, 0)
    struct.pack_into("<H", header, 0x10, load)
    struct.pack_into("<H", header, 0x12, entry)
    struct.pack_into("<H", header, 0x14, stack)
    return bytes(header)


def make_low_copy_loader(
    loader_load: int,
    source: int,
    target: int,
    size: int,
    stack: int,
    entry: int,
) -> bytes:
    """Return a tiny direct-load trampoline.

    This is not DSS PRELOAD: LOADER stays zero, so DSS loads the whole EXE body
    at loader_load. The trampoline copies the C image down to the Scheme C
    address below 0x4100, restores the SDK stack, and jumps to crt0 _entry.
    """

    for name, value in {
        "loader_load": loader_load,
        "source": source,
        "target": target,
        "size": size,
        "stack": stack,
        "entry": entry,
    }.items():
        if not 0 <= value <= 0xFFFF:
            raise SystemExit(f"dss_exe: {name}=0x{value:X} is outside Z80 address space")
    if size == 0:
        raise SystemExit("dss_exe: low-loader image is empty")

    return bytes(
        [
            0xF3,  # di
            0x21, source & 0xFF, source >> 8,  # ld hl,source
            0x11, target & 0xFF, target >> 8,  # ld de,target
            0x01, size & 0xFF, size >> 8,  # ld bc,size
            0xED, 0xB0,  # ldir
            0x31, stack & 0xFF, stack >> 8,  # ld sp,stack
            0xC3, entry & 0xFF, entry >> 8,  # jp entry
        ]
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="input .ihx")
    parser.add_argument("output", type=Path, help="output .exe")
    parser.add_argument("--load", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--entry", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--stack", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--assets", type=Path, help="append raw/packed assets after code")
    parser.add_argument(
        "--low-loader-load",
        type=lambda value: int(value, 0),
        default=DSS_MIN_LOAD,
        help="DSS load address for the direct low-address copy loader",
    )
    parser.add_argument(
        "--allow-low-load",
        action="store_true",
        help="allow load addresses below DSS direct EXE range; loader-stage use only",
    )
    args = parser.parse_args(argv)

    code = contiguous_image(parse_ihx(args.input), args.load)
    assets = args.assets.read_bytes() if args.assets else b""

    if args.load < DSS_MIN_LOAD and not args.allow_low_load:
        loader_load = args.low_loader_load
        if loader_load < DSS_MIN_LOAD:
            raise SystemExit(
                f"dss_exe: low-loader load address 0x{loader_load:04X} is below "
                f"DSS minimum 0x{DSS_MIN_LOAD:04X}"
            )
        source = loader_load + LOW_COPY_LOADER_SIZE
        # The copy destination must not reach the loader itself: ldir writes
        # [args.load .. args.load+len(code)) while the loader executes at
        # loader_load, so the relocated image must end at or below it.
        if args.load + len(code) > loader_load:
            raise SystemExit(
                f"dss_exe: relocated code 0x{args.load:04X}+{len(code)} reaches the "
                f"low-loader at 0x{loader_load:04X}; the PRELOAD file-reading loader "
                "is required for this project"
            )
        direct_end = source + len(code) + len(assets)
        if direct_end > 0x10000:
            raise SystemExit(
                "dss_exe: direct low-loader body does not fit below 0x10000; "
                "the PRELOAD file-reading loader is required for this project"
            )
        loader = make_low_copy_loader(
            loader_load=loader_load,
            source=source,
            target=args.load,
            size=len(code),
            stack=args.stack,
            entry=args.entry,
        )
        if len(loader) != LOW_COPY_LOADER_SIZE:
            raise SystemExit(
                f"dss_exe: low-loader is {len(loader)} bytes but LOW_COPY_LOADER_SIZE="
                f"{LOW_COPY_LOADER_SIZE}; source offset would be wrong"
            )
        exe = make_header(loader_load, loader_load, args.stack) + loader + code + assets
        mode = (
            f"low-loader load=0x{loader_load:04X}, copy=0x{source:04X}->0x{args.load:04X}, "
            f"entry=0x{args.entry:04X}"
        )
    else:
        if args.load < DSS_MIN_LOAD:
            mode = "format-only low-load"
        else:
            mode = "direct"
        exe = make_header(args.load, args.entry, args.stack) + code + assets

    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_name(args.output.name + ".tmp")
    tmp.write_bytes(exe)
    tmp.replace(args.output)

    print(
        f"dss_exe: wrote {args.output} "
        f"(mode={mode}, code={len(code)} bytes, assets={len(assets)} bytes, "
        f"stack=0x{args.stack:04X})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
