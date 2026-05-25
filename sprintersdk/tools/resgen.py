#!/usr/bin/env python3
"""
Generate EvoSDK-compatible resources.h from a compile.bat manifest.

This is a Python replacement for evosdk/tools_src/makeresh/makeresh.cpp.
It intentionally keeps the old identifier contract:

* `set image.N=foo.bmp`      -> `#define IMG_FOO <sequential id>`
* `set palette.N=foo.bmp`    -> `#define PAL_FOO <sequential id>`
* `set music.N=foo.pt3`      -> `#define MUS_FOO <sequential id>`
* `set sample.N=foo.wav`     -> `#define SMP_FOO <sequential id>`
* `set sprite.N=sheet.bmp`   -> `#define SPR_SHEET <base sprite id>`
* `set soundfx=bank.afb`     -> `#define SFX_NAME <effect id>`

The old .bat pipeline enumerated Windows environment variables with
`SET image`, `SET palette`, etc. That order is lexicographic by variable
name, so `image.10` comes before `image.2`. We reproduce that ordering
instead of treating N as the final resource ID.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import sys
from pathlib import Path


SET_RE = re.compile(r"^\s*set\s+([A-Za-z_][A-Za-z0-9_]*)(?:\.([^=\s]+))?\s*=\s*(.*?)\s*$", re.IGNORECASE)

RESOURCE_PREFIXES = {
    "image": "IMG_",
    "palette": "PAL_",
    "music": "MUS_",
    "sample": "SMP_",
}


def warn(msg: str) -> None:
    print(f"resgen: warning: {msg}", file=sys.stderr)


def decode_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8-sig", "cp1251", "cp866", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise SystemExit(f"resgen: cannot decode {path}")


def strip_bat_value(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value.strip()


def parse_compile_bat(path: Path) -> tuple[dict[str, list[tuple[str, Path]]], Path | None]:
    base = path.parent
    entries: dict[str, list[tuple[str, Path]]] = {
        "image": [],
        "palette": [],
        "music": [],
        "sample": [],
        "sprite": [],
    }
    soundfx: Path | None = None

    for line in decode_text(path).splitlines():
        if re.match(r"^\s*rem(?:\s|$)", line, re.IGNORECASE):
            continue

        match = SET_RE.match(line)
        if not match:
            continue

        key, suffix, value = match.group(1).lower(), match.group(2), strip_bat_value(match.group(3))
        if not value:
            continue

        var_name = key if suffix is None else f"{key}.{suffix}"
        normalized_value = value.replace("\\", os.sep).replace("/", os.sep)

        if key == "soundfx" and suffix is None:
            soundfx = (base / normalized_value)
            continue

        if suffix is None:
            continue

        # The original `_compile.bat` collected variables with `SET sprite`;
        # that also included accidental/plural `sprites.N` variables.
        if key == "sprites":
            key = "sprite"

        if key in entries:
            entries[key].append((var_name.lower(), base / normalized_value))

    for values in entries.values():
        values.sort(key=lambda item: item[0])

    return entries, soundfx


def resource_name(path: Path) -> str:
    name = path.name
    stem = name.rsplit(".", 1)[0] if "." in name else name
    out = []
    for char in stem:
        if "0" <= char <= "9" or "A" <= char <= "Z":
            out.append(char)
        elif "a" <= char <= "z":
            out.append(char.upper())
        else:
            out.append("_")
    return "".join(out)


def read_u16_le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def read_u32_le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)


def bmp_sprite_count(path: Path) -> tuple[int | None, str | None]:
    """Sprite count of a 16x16-sheet BMP. Returns (count, None) on success,
    or (None, reason) when the sheet must be skipped (so the caller can warn:
    skipping shifts the IDs of every later sprite)."""
    if not path.exists():
        return None, "file not found"
    try:
        header = path.read_bytes()[:34]
    except OSError as exc:
        return None, f"read error: {exc}"

    if len(header) < 34 or header[:2] != b"BM":
        return None, "not a BMP file"

    bpp = read_u16_le(header, 28)
    compression = read_u32_le(header, 30)
    width = read_u32_le(header, 18)
    height = read_u32_le(header, 22)

    if bpp != 8 or compression != 0:
        return None, f"need uncompressed 8bpp (got bpp={bpp}, compression={compression})"
    if (width & 15) or (height & 15):
        return None, f"size must be a multiple of 16 (got {width}x{height})"

    return (width >> 4) * (height >> 4), None


def skip_effect(data: bytes) -> int:
    pos = 0
    size = len(data)

    while pos < size:
        item = data[pos]
        pos += 1

        if item & (1 << 5):
            pos += 2

        if item & (1 << 6):
            if pos >= size:
                break
            noise = data[pos]
            pos += 1
            if item == 0xD0 and noise >= 0x20:
                break

        if pos > size:
            return size

    return pos


def soundfx_defines(path: Path) -> list[tuple[str, int]]:
    try:
        data = path.read_bytes()
    except OSError:
        warn(f"soundfx '{path}' not found (no SFX_ defines emitted)")
        return []

    if not data:
        warn(f"soundfx '{path}' is empty (no SFX_ defines emitted)")
        return []

    count = data[0]
    out: list[tuple[str, int]] = []

    for index in range(count):
        table_pos = 1 + index * 2
        if table_pos + 2 > len(data):
            break

        off = read_u16_le(data, table_pos) + 2 + index * 2
        if index < count - 1 and table_pos + 4 <= len(data):
            length = read_u16_le(data, table_pos + 2) + 4 + index * 2 - off
        else:
            length = len(data) - off

        if off < 0 or length < 0 or off > len(data):
            continue

        effect = data[off:off + length]
        name_pos = skip_effect(effect)
        if name_pos < len(effect):
            raw_name = effect[name_pos:].split(b"\0", 1)[0]
            name = raw_name.decode("latin-1", errors="ignore")
        else:
            name = f"noname{index + 1:03d}"

        out.append((make_define_name(name), index))

    return out


def make_define_name(value: str) -> str:
    out = []
    for char in value:
        if "0" <= char <= "9" or "A" <= char <= "Z":
            out.append(char)
        elif "a" <= char <= "z":
            out.append(char.upper())
        else:
            out.append("_")
    return "".join(out)


def build_header(entries: dict[str, list[tuple[str, Path]]], soundfx: Path | None) -> str:
    lines = [
        "/* Auto-generated by sprintersdk/tools/resgen.py. Do not edit. */",
        "",
    ]

    for kind in ("image", "palette", "music", "sample"):
        prefix = RESOURCE_PREFIXES[kind]
        resource_id = 0
        for var_name, path in entries[kind]:
            # ID still emitted from the filename (makeresh contract), but a
            # missing file almost certainly means a typo'd manifest entry.
            if not path.exists():
                warn(f"{kind} '{var_name}' -> '{path}' not found")
            lines.append(f"#define {prefix}{resource_name(path)}\t{resource_id}")
            resource_id += 1
        lines.append("")

    sprite_id = 0
    for var_name, path in entries["sprite"]:
        count, reason = bmp_sprite_count(path)
        if count is None:
            warn(f"sprite '{var_name}' -> '{path}' skipped: {reason}"
                 f" -- SPR_ IDs of later sheets will shift")
            continue
        lines.append(f"#define SPR_{resource_name(path)}\t{sprite_id}")
        sprite_id += count
    lines.append("")

    if soundfx is not None:
        for name, effect_id in soundfx_defines(soundfx):
            lines.append(f"#define SFX_{name}\t{effect_id}")

    if lines[-1] != "":
        lines.append("")

    return "\n".join(lines)


def write_if_changed(path: Path, data: str) -> None:
    old = None
    try:
        old = path.read_text(encoding="utf-8")
    except OSError:
        pass
    except UnicodeDecodeError:
        pass

    if old == data:
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(data, encoding="utf-8", newline="\n")
    tmp.replace(path)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate EvoSDK resources.h from compile.bat")
    parser.add_argument("manifest", type=Path, help="project compile.bat")
    parser.add_argument("-o", "--output", type=Path, default=Path("resources.h"), help="output resources.h")
    args = parser.parse_args(argv)

    entries, soundfx = parse_compile_bat(args.manifest)
    write_if_changed(args.output, build_header(entries, soundfx))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
