#!/usr/bin/env python3
"""Wrap a binary file into an optional HRUST-packed SPK1 container."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


MAGIC = b"SPK1"
VERSION = 1
CHUNK_SIZE = 0x4000
FLAG_RAW = 0
FLAG_HRUST = 1


def default_mhmt() -> Path:
    env = os.environ.get("MHMT")
    if env:
        return Path(env)
    return Path(__file__).resolve().parent / "bin" / "mhmt"


def run_tool(args: list[str]) -> bytes:
    try:
        result = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        output = exc.stdout.decode("utf-8", errors="replace") if exc.stdout else ""
        raise SystemExit(f"pack_spk: tool failed: {' '.join(args)}\n{output}") from exc
    return result.stdout


def pack_chunk(mhmt: Path, chunk: bytes, index: int, tmpdir: Path) -> tuple[int, bytes]:
    raw = tmpdir / f"chunk{index:03d}.raw"
    packed = tmpdir / f"chunk{index:03d}.hst"
    depacked = tmpdir / f"chunk{index:03d}.dpk"

    raw.write_bytes(chunk)
    run_tool([str(mhmt), "-hst", "-zxh", str(raw), str(packed)])
    packed_data = packed.read_bytes()

    if len(packed_data) >= len(chunk) or len(packed_data) > CHUNK_SIZE:
        return FLAG_RAW, chunk

    run_tool([str(mhmt), "-d", "-hst", "-zxh", str(packed), str(depacked)])
    if depacked.read_bytes() != chunk:
        raise SystemExit(f"pack_spk: mhmt verification failed for chunk {index}")

    return FLAG_HRUST, packed_data


def pack_file(src: Path, dst: Path, mhmt: Path) -> None:
    data = src.read_bytes()
    chunks = [data[pos:pos + CHUNK_SIZE] for pos in range(0, len(data), CHUNK_SIZE)]
    if not chunks:
        chunks = [b""]
    if len(chunks) > 255:
        raise SystemExit("pack_spk: input is too large: more than 255 chunks")

    dst.parent.mkdir(parents=True, exist_ok=True)
    packed_count = 0
    saved = 0

    with tempfile.TemporaryDirectory(prefix="spevo-spk-") as tmp:
        tmpdir = Path(tmp)
        tmp_out = dst.with_name(dst.name + ".tmp")
        with tmp_out.open("wb") as out:
            out.write(MAGIC)
            out.write(bytes((VERSION, len(chunks), 0, 0)))
            for index, chunk in enumerate(chunks):
                flag, payload = pack_chunk(mhmt, chunk, index, tmpdir)
                if flag == FLAG_HRUST:
                    packed_count += 1
                    saved += len(chunk) - len(payload)
                out.write(bytes((flag,)))
                out.write(len(chunk).to_bytes(2, "little"))
                out.write(len(payload).to_bytes(2, "little"))
                out.write(payload)
        tmp_out.replace(dst)

    print(
        f"pack_spk: wrote {dst} ({len(data)} -> {dst.stat().st_size} bytes, "
        f"{packed_count}/{len(chunks)} chunks packed, saved {saved})"
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mhmt", type=Path, default=default_mhmt(), help="path to mhmt")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)

    if not args.mhmt.is_file() or not os.access(args.mhmt, os.X_OK):
        raise SystemExit(f"pack_spk: mhmt is not executable: {args.mhmt}")

    pack_file(args.input, args.output, args.mhmt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
