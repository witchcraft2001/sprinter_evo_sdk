#!/usr/bin/env python3
"""
Build an EVOS asset bundle for the Sprinter EvoSDK port.

Input is the original project `compile.bat`. Output is `assets.dat`:

    header:  u32 magic 'EVOS', u16 version, u16 records, u32 file_size, u32 zero
    record:  u8 type, u8 id, u16 width, u16 height, u16 reserved, u32 offset, u32 length
    data:    record payloads

The generated IDs use the same Windows-`SET` lexicographic order as resgen.py
and the original makeresh.exe.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path

try:
    from resgen import (parse_compile_bat, parse_sprinter_overrides, parse_palette_base,
                        parse_palette_ui, resource_name, bmp_sprite_count, warn,
                        decode_text, png_ihdr)
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from resgen import (parse_compile_bat, parse_sprinter_overrides, parse_palette_base,
                        parse_palette_ui, resource_name, bmp_sprite_count, warn,
                        decode_text, png_ihdr)

import tempfile

# Lazily-created scratch dir for palette_base reserved-layout BMPs (process-lived).
_RESERVED_TMPDIR: Path | None = None


TYPE_PAL = 0
TYPE_IMG = 1
TYPE_SPR = 2
TYPE_MUS = 3
TYPE_SFX = 4
TYPE_SAM = 5

MAGIC = 0x534F5645  # 'EVOS'
VERSION = 4
HEADER_FMT = "<IHHI4x"
RECORD_FMT = "<BBHHHII"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
RECORD_SIZE = struct.calcsize(RECORD_FMT)

# Sprite transparency threshold: a cell pixel >= this index is baked to 0xFF
# (HW-transparent on #5C). Default 16 = the EvoSDK 16-colour convention (colours
# 0..15, everything above transparent). --pal256 sets it to 255 so 256-colour
# sprites use colours 0..254 with only index 255 transparent (§9.1).
SPRITE_TRANSPARENT_MIN = 16
DEFAULT_PT3_PLAYER = Path(__file__).resolve().parent.parent / "pt3play.asm"
DEFAULT_AFX_PLAYER = Path(__file__).resolve().parent.parent / "ayfxplay.asm"

# Hardware-keyed flag, stored in bit 0 of the IMG meta record's dedicated flags
# byte (the 5th byte). When set, draw_tile_key uses the WIN3=#58 HW path. Kept
# OUT of base_tile: the old "bit 15 of base_tile" scheme capped image tile space
# at 0x8000 and SILENTLY corrupted any image past it (robo's later MAIN frames
# wrapped to tile 168/1168 -> garbage). base_tile is now a full u16.
IMG_FLAG_HW_KEYED = 0x01

COLOR_KEY_RE = re.compile(
    r"^\s*set\s+color_key\.(\w+)\s*=\s*(\d+)", re.IGNORECASE
)


@dataclass
class Record:
    type: int
    id: int
    width: int
    height: int
    reserved: int
    data: bytes
    name: str


def get_u16(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def get_u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def read_bmp(path: Path) -> tuple[list[tuple[int, int, int]], bytes, int, int, int]:
    if not path.exists():
        raise SystemExit(f"assetpack: {path}: file not found")
    data = path.read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        raise SystemExit(f"assetpack: {path}: not a BMP")

    pixel_off = get_u32(data, 10)
    dib_size = get_u32(data, 14)
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    bpp = get_u16(data, 28)
    compression = get_u32(data, 30)

    if width <= 0 or height == 0:
        raise SystemExit(f"assetpack: {path}: invalid BMP dimensions {width}x{height}")
    if compression != 0:
        raise SystemExit(f"assetpack: {path}: compressed BMP is not supported")
    if bpp not in (4, 8, 24, 32):
        raise SystemExit(f"assetpack: {path}: only 4/8/24/32bpp BMP is supported")

    if bpp in (24, 32):
        # Truecolour BMP: no palette in the file. Collapse distinct colours into a
        # palette (<=256), like read_png's truecolour path -- no lossy quantisation,
        # so reduce the colour count (or export indexed) if this raises. Alpha (32bpp
        # X/A byte) is ignored: BMP keeps the legacy non-alpha transparency rule.
        step = bpp // 8
        row_bytes = ((bpp * width + 31) // 32) * 4
        abs_height = abs(height)
        bottom_up = height > 0
        pixels = bytearray(width * abs_height)
        pal_map: dict = {}
        palette: list[tuple[int, int, int]] = []
        for src_y in range(abs_height):
            row_off = pixel_off + src_y * row_bytes
            if row_off + row_bytes > len(data):
                raise SystemExit(f"assetpack: {path}: short BMP pixel data")
            dst = (abs_height - 1 - src_y if bottom_up else src_y) * width
            for x in range(width):
                o = row_off + x * step
                rgb = (data[o + 2], data[o + 1], data[o])     # BGR -> RGB
                j = pal_map.get(rgb)
                if j is None:
                    if len(palette) >= 256:
                        raise SystemExit(f"assetpack: {path}: >256 distinct colours -- "
                                         "export as an indexed BMP/PNG or reduce the colour count")
                    j = len(palette); pal_map[rgb] = j; palette.append(rgb)
                pixels[dst + x] = j
        return palette, bytes(pixels), width, abs_height, 8

    palette_count = 16 if bpp == 4 else 256
    palette_off = 14 + dib_size
    palette: list[tuple[int, int, int]] = []
    for i in range(palette_count):
        off = palette_off + i * 4
        if off + 4 > len(data):
            raise SystemExit(f"assetpack: {path}: short BMP palette")
        b, g, r, _zero = data[off:off + 4]
        palette.append((r, g, b))

    row_bytes = ((bpp * width + 31) // 32) * 4
    abs_height = abs(height)
    bottom_up = height > 0
    pixels = bytearray(width * abs_height)

    for src_y in range(abs_height):
        row_off = pixel_off + src_y * row_bytes
        if row_off + row_bytes > len(data):
            raise SystemExit(f"assetpack: {path}: short BMP pixel data")
        dst_y = abs_height - 1 - src_y if bottom_up else src_y
        dst = dst_y * width

        if bpp == 4:
            for x in range(width):
                packed = data[row_off + x // 2]
                pixels[dst + x] = (packed >> 4) if (x & 1) == 0 else (packed & 0x0F)
        else:
            pixels[dst:dst + width] = data[row_off:row_off + width]

    return palette, bytes(pixels), width, abs_height, bpp


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path: Path) -> tuple[list[tuple[int, int, int]], bytes, int, int, int, bytes]:
    """Decode a non-interlaced PNG to (palette, index_pixels, w, h, 8, transparent).
    `transparent` is a w*h bytes mask: 1 = the pixel is not fully opaque (alpha<255)
    and is baked to 0xFF downstream for hardware transparency. Indexed PNG (colour
    type 3) keeps its PLTE order (so palette-partitioning / colour_key conventions
    survive); grey/truecolour PNG builds a palette from its distinct OPAQUE colours
    (must be <=256 -- no lossy quantisation here)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"assetpack: {path}: not a PNG")
    pos = 8
    width = height = bit_depth = colour = interlace = None
    plte = b""
    trns: bytes | None = None
    idat = bytearray()
    while pos + 8 <= len(data):
        ln = int.from_bytes(data[pos:pos + 4], "big")
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln                          # length(4)+type(4)+data(ln)+crc(4)
        if typ == b"IHDR":
            width = int.from_bytes(chunk[0:4], "big")
            height = int.from_bytes(chunk[4:8], "big")
            bit_depth, colour, interlace = chunk[8], chunk[9], chunk[12]
        elif typ == b"PLTE":
            plte = chunk
        elif typ == b"tRNS":
            trns = chunk
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    if width is None:
        raise SystemExit(f"assetpack: {path}: missing PNG IHDR")
    if interlace:
        raise SystemExit(f"assetpack: {path}: interlaced PNG not supported (save non-interlaced)")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour)
    if channels is None or bit_depth not in (1, 2, 4, 8, 16):
        raise SystemExit(f"assetpack: {path}: unsupported PNG (colour type {colour}, bit depth {bit_depth})")

    raw = zlib.decompress(bytes(idat))
    bits_per_pixel = bit_depth * channels
    stride = (width * bits_per_pixel + 7) // 8
    bpp = max(1, bits_per_pixel // 8)           # byte step for the filter predictors

    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for _y in range(height):
        ft = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if ft == 1:
            for i in range(stride):
                line[i] = (line[i] + (line[i - bpp] if i >= bpp else 0)) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 0xFF
        elif ft != 0:
            raise SystemExit(f"assetpack: {path}: bad PNG filter type {ft}")
        out += line
        prev = line

    maxval = (1 << bit_depth) - 1

    def iter_pixels():
        for y in range(height):
            row = out[y * stride:(y + 1) * stride]
            if bit_depth == 8:
                k = 0
                for _x in range(width):
                    yield row[k:k + channels]; k += channels
            elif bit_depth == 16:
                k = 0
                for _x in range(width):
                    yield [row[k + c * 2] for c in range(channels)]; k += channels * 2   # high byte
            else:                                # 1/2/4-bit (indexed or grey, 1 channel)
                bitpos = 0
                for _x in range(width):
                    shift = 8 - bit_depth - (bitpos & 7)
                    yield [(row[bitpos >> 3] >> shift) & maxval]
                    bitpos += bit_depth

    pixels = bytearray(width * height)
    transparent = bytearray(width * height)

    if colour == 3:                              # indexed: keep PLTE order, alpha from tRNS
        palette = [tuple(plte[i:i + 3]) for i in range(0, len(plte), 3)]
        idx_alpha = trns if trns is not None else b""
        for i, s in enumerate(iter_pixels()):
            v = s[0]
            pixels[i] = v
            if v < len(idx_alpha) and idx_alpha[v] < 255:
                transparent[i] = 1
        return palette, bytes(pixels), width, height, 8, bytes(transparent)

    # grey / truecolour: collapse distinct opaque colours into a palette (<=256)
    def scale(v):
        return v if bit_depth >= 8 else (v * 255 // maxval)

    key = None                                   # tRNS colour key for type 0/2
    if trns is not None and colour == 0:
        key = (int.from_bytes(trns[0:2], "big"),)
    elif trns is not None and colour == 2:
        key = tuple(int.from_bytes(trns[i:i + 2], "big") for i in (0, 2, 4))

    pal_map: dict = {}
    palette = []
    for i, s in enumerate(iter_pixels()):
        if colour == 0:
            alpha = 0 if key is not None and (s[0],) == key else 255
            rgb = (scale(s[0]),) * 3
        elif colour == 4:
            alpha = s[1]; rgb = (scale(s[0]),) * 3
        elif colour == 2:
            alpha = 0 if key is not None and tuple(s) == key else 255
            rgb = (scale(s[0]), scale(s[1]), scale(s[2]))
        else:                                    # colour == 6 (RGBA)
            alpha = s[3]; rgb = (scale(s[0]), scale(s[1]), scale(s[2]))
        if alpha < 255:
            transparent[i] = 1                   # pixels[i] stays 0; baked to 0xFF later
            continue
        j = pal_map.get(rgb)
        if j is None:
            if len(palette) >= 256:
                raise SystemExit(f"assetpack: {path}: >256 distinct opaque colours -- "
                                 "export as an indexed PNG or reduce the colour count")
            j = len(palette); pal_map[rgb] = j; palette.append(rgb)
        pixels[i] = j
    return palette, bytes(pixels), width, height, 8, bytes(transparent)


def read_image(path: Path):
    """Unified reader: BMP or PNG. Returns (palette, pixels, w, h, bpp, transparent),
    where `transparent` is a w*h 0/1 bytes mask for PNG, or None for BMP (which keeps
    the legacy index-threshold transparency rule)."""
    if png_ihdr(path) is not None:
        return read_png(path)
    palette, pixels, w, h, bpp = read_bmp(path)
    return palette, pixels, w, h, bpp, None


def pack_palette(path: Path) -> bytes:
    palette, _pixels, _width, _height, _bpp, _t = read_image(path)
    # The runtime picks the 256-colour path purely by count >= 256 (high byte != 0);
    # BMP only ever yields 16 or 256, but a PNG palette can be any size. Pad any
    # >16-colour palette out to 256 so it takes the 256-colour path (apply_palette_256
    # writes all 256 entries); 16 or fewer stays on the 16-colour RGB222 path.
    count = len(palette)
    if count > 16:
        palette = list(palette) + [(0, 0, 0)] * (256 - count)
        count = 256
    payload = bytearray()
    payload += struct.pack("<H", count)
    for r, g, b in palette[:count]:
        payload += bytes((r, g, b))
    return bytes(payload)


def parse_color_keys(manifest: Path) -> dict[str, int]:
    """`set color_key.N=K` -> {N: K}. Declares image.N as drawn ONLY keyed,
    with palette index K transparent; assetpack remaps K->0xFF and the runtime
    uses the HW #58 path. Keyed indices come back keyed off the image's suffix
    N (same N as image.N)."""
    keys: dict[str, int] = {}
    for line in decode_text(manifest).splitlines():
        m = COLOR_KEY_RE.match(line)
        if m:
            keys[m.group(1).lower()] = int(m.group(2))
    return keys


def pack_image(path: Path, remap_key: int | None = None) -> tuple[bytes, int, int, bool]:
    """Pack an image into 8x8 tiles. Returns (payload, w, h, keyed) where `keyed`
    is True if the image carries transparency (PNG alpha or a declared color_key)
    and must be drawn through the HW #58 keyed path (0xFF = transparent)."""
    _palette, pixels, width, height, _bpp, transparent = read_image(path)
    if (width & 7) or (height & 7):
        raise SystemExit(f"assetpack: {path}: image dimensions must be 8px aligned")

    # HW transparency (#58) only skips 0xFF. Bake transparent pixels to 0xFF so the
    # runtime can blit via #58 with no CPU compare. Two sources of transparency:
    #   * PNG alpha: any pixel with alpha<255 (per the `transparent` mask);
    #   * a declared `color_key.N=K`: palette index K (BMP legacy / extra keying).
    keyed = False
    if transparent is not None and any(transparent):
        pixels = bytes(0xFF if transparent[i] else pixels[i] for i in range(len(pixels)))
        keyed = True
    if remap_key is not None:
        pixels = bytes(0xFF if b == remap_key else b for b in pixels)
        keyed = True

    out = bytearray()
    for ty in range(0, height, 8):
        for tx in range(0, width, 8):
            for row in range(8):
                off = (ty + row) * width + tx
                out += pixels[off:off + 8]

    return bytes(out), width, height, keyed


def pack_sprites(path: Path, base_id: int) -> tuple[list[Record], int]:
    # The skip decision and cell count come from resgen.bmp_sprite_count, so
    # SPR_ IDs in assets.dat stay byte-for-byte in step with resources.h and
    # with the original makeresh: only present, uncompressed-8bpp, 16-aligned
    # sheets are packed. A skipped sheet does NOT advance the sprite id (this
    # is exactly what resgen does -- diverging here desyncs every later SPR_).
    count, reason = bmp_sprite_count(path)
    if count is None:
        warn(f"sprite '{path}' skipped: {reason}"
             f" -- matches resgen; later SPR_ IDs unaffected")
        return [], 0

    _palette, pixels, width, height, _bpp, transparent = read_image(path)
    sheet_name = resource_name(path)
    records: list[Record] = []
    cols = width // 16

    for index in range(count):
        sprite_id = base_id + index
        if sprite_id > 255:
            warn(f"{path}: sprite cell {index} exceeds id 255, not packed"
                 f" (sprite id space is u8)")
            break

        sx = (index % cols) * 16
        sy = (index // cols) * 16
        payload = bytearray(16 * 16)
        for y in range(16):
            for x in range(16):
                src = (sy + y) * width + sx + x
                pixel = pixels[src]
                if transparent is not None:
                    # PNG: transparency is the alpha mask only (alpha<255 -> 0xFF);
                    # opaque pixels keep their palette index regardless of value.
                    payload[y * 16 + x] = 0xFF if transparent[src] else pixel
                else:
                    # BMP: legacy index-threshold rule (>=16, or >=255 with --pal256).
                    payload[y * 16 + x] = 0xFF if pixel >= SPRITE_TRANSPARENT_MIN else pixel

        name = sheet_name if index == 0 else f"{sheet_name}_{index}"
        records.append(Record(TYPE_SPR, sprite_id, 16, 16, 0, bytes(payload), name))

    # Advance by the full cell count (matches resgen), even if records were
    # truncated at id 255 -- those cells are unaddressable anyway.
    return records, count


def parse_wav(path: Path) -> tuple[bytes, int]:
    if not path.exists():
        raise SystemExit(f"assetpack: {path}: WAV file not found")
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return data, 22050

    pos = 12
    fmt = None
    channels = None
    rate = 22050
    bits = None
    pcm = None

    while pos + 8 <= len(data):
        chunk = data[pos:pos + 4]
        size = get_u32(data, pos + 4)
        payload = data[pos + 8:pos + 8 + size]
        if chunk == b"fmt " and len(payload) >= 16:
            fmt, channels, rate, _byte_rate, _align, bits = struct.unpack_from("<HHIIHH", payload, 0)
        elif chunk == b"data":
            pcm = payload
        pos += 8 + size + (size & 1)

    if pcm is None:
        raise SystemExit(f"assetpack: {path}: WAV data chunk not found")
    if fmt != 1 or channels not in (1, 2) or bits not in (8, 16):
        raise SystemExit(f"assetpack: {path}: only 8/16-bit PCM mono/stereo WAV is supported")

    if channels == 1 and bits == 8:
        return pcm, rate

    step = channels * (bits // 8)
    out = bytearray()
    for off in range(0, len(pcm) - step + 1, step):
        acc = 0
        for ch in range(channels):
            sample_off = off + ch * (bits // 8)
            if bits == 8:
                acc += pcm[sample_off] - 128
            else:
                acc += struct.unpack_from("<h", pcm, sample_off)[0] >> 8
        out.append((128 + acc // channels) & 0xFF)

    return bytes(out), rate


def cbl_ctrl_for_rate(rate: int) -> int:
    # CBL control byte written to port #004E (DCP-mapped). Bit layout (matches the
    # MK_DEMO/MK_OUTI players that run on real hardware AND the emulator):
    #   bit7 MODE, bit6 STEREO, bit5 16-bit, bit4 INT_ENA, bits[3:0] rate index.
    # Mono 8-bit + INT -> 0x90 | rate. Rate idx: 9=10.9k 10=15.6k 11=21.9k 12=31.25k.
    # NOTE: the old #D9/#DA/#DB ALSO set STEREO+16-bit, so a mono 8-bit sample was
    # played as stereo 16-bit -> grinding noise + stretched duration on hardware.
    if rate <= 12000:
        return 0x99
    if rate <= 17000:
        return 0x9A
    if rate <= 26000:
        return 0x9B
    return 0x9C


def run_tool(args: list[str]) -> None:
    try:
        subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        output = exc.stdout.decode("utf-8", errors="replace") if exc.stdout else ""
        raise SystemExit(f"assetpack: tool failed: {' '.join(args)}\n{output}") from exc


def sjasmplus_path() -> str:
    return os.environ.get("SJASMPLUS", "sjasmplus")


def pt3_player_path() -> Path:
    return Path(os.environ.get("PT3_PLAYER", str(DEFAULT_PT3_PLAYER)))


def afx_player_path() -> Path:
    return Path(os.environ.get("AFX_PLAYER", str(DEFAULT_AFX_PLAYER)))


def pack_music_pt3(path: Path) -> bytes:
    if not path.exists():
        raise SystemExit(f"assetpack: {path}: music file not found")
    if path.stat().st_size == 0:
        raise SystemExit(f"assetpack: {path}: empty music file")

    player = pt3_player_path()
    if not player.exists():
        raise SystemExit(f"assetpack: PT3 player not found: {player}")

    with tempfile.TemporaryDirectory(prefix="spevo-pt3-") as tmp:
        tmpdir = Path(tmp)
        wrapper = tmpdir / "pt3_image.asm"
        output = tmpdir / "pt3_image.bin"
        wrapper.write_text(
            "\n".join(
                [
                    "        device zxspectrum128",
                    "        org #C000",
                    "PlayerStart:",
                    f'        include "{player.resolve()}"',
                    "MusicModule:",
                    f'        incbin "{path.resolve()}"',
                    "PlayerEnd:",
                    f'        savebin "{output}",PlayerStart,PlayerEnd-PlayerStart',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        run_tool([sjasmplus_path(), str(wrapper)])
        data = output.read_bytes()

    if len(data) > PAGE:
        raise SystemExit(
            f"assetpack: {path}: PT3 player+module is {len(data)} bytes, exceeds 16K page"
        )
    return data


def pack_soundfx_afx(path: Path) -> bytes:
    if not path.exists():
        raise SystemExit(f"assetpack: {path}: soundfx bank not found")
    if path.stat().st_size == 0:
        raise SystemExit(f"assetpack: {path}: empty soundfx bank")

    player = afx_player_path()
    if not player.exists():
        raise SystemExit(f"assetpack: AFX player not found: {player}")

    with tempfile.TemporaryDirectory(prefix="spevo-afx-") as tmp:
        tmpdir = Path(tmp)
        wrapper = tmpdir / "afx_image.asm"
        output = tmpdir / "afx_image.bin"
        wrapper.write_text(
            "\n".join(
                [
                    "        device zxspectrum128",
                    "        org #C000",
                    "SfxStart:",
                    "        jp SfxInit",
                    "        jp ayfx.PLAY",
                    "        jp ayfx.FRAME",
                    "SfxInit:",
                    "        ld hl,SfxBank",
                    "        jp ayfx.INIT",
                    f'        include "{player.resolve()}"',
                    "SfxBank:",
                    f'        incbin "{path.resolve()}"',
                    "SfxEnd:",
                    f'        savebin "{output}",SfxStart,SfxEnd-SfxStart',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        run_tool([sjasmplus_path(), str(wrapper)])
        data = output.read_bytes()

    if len(data) > PAGE:
        raise SystemExit(
            f"assetpack: {path}: AFX player+bank is {len(data)} bytes, exceeds 16K page"
        )
    return data


def _write_indexed_bmp(path: Path, w: int, h: int, idx_pixels, palette256) -> None:
    """Write a standard 8bpp BMP: 256-entry BGR0 palette + bottom-up indexed rows."""
    row = ((8 * w + 31) // 32) * 4
    pix_off = 14 + 40 + 256 * 4
    img = row * h
    out = bytearray()
    out += b"BM" + struct.pack("<IHHI", pix_off + img, 0, 0, pix_off)
    out += struct.pack("<IiiHHIIiiII", 40, w, h, 1, 8, 0, img, 2835, 2835, 256, 0)
    pal = list(palette256) + [(0, 0, 0)] * (256 - len(palette256))
    for (r, g, b) in pal[:256]:
        out += bytes((b, g, r, 0))
    pad = row - w
    for sy in range(h):
        y = h - 1 - sy                      # bottom-up
        out += bytes(idx_pixels[y * w + x] for x in range(w)) + bytes(pad)
    path.write_bytes(out)


def _reserved_layout_bmp(base_path: Path, override_path: Path, base_index: int,
                         ui_palette_path: Path | None = None) -> Path:
    """Build an 8bpp BMP whose palette is [base 16-colour palette at 0..15] +
    [override image's colours at base_index..255], with the override's pixels
    remapped accordingly (§9.1 palette partitioning). Colours beyond the 256-
    base_index budget are merged into their nearest kept colour (least-frequent
    first). Returns the path to a temp BMP. Dimensions follow the override.

    If `ui_palette_path` is given (palette_ui.N), indices 1..15 come from THAT
    file's palette instead of `base_path` -- so UI/text drawn over the photo (e.g.
    the win-screen `end` dialog) uses the normal in-game palette. Index 0 is KEPT
    from `base_path`: it is the SDK clear/letterbox/transparent colour (clear_screen
    fills it, draw_image leaves the centring margins at it), so it must stay the
    screen's own background (black) rather than the UI palette's index 0. The photo
    always lands in base_index..255 and is unaffected either way."""
    global _RESERVED_TMPDIR
    if _RESERVED_TMPDIR is None:
        _RESERVED_TMPDIR = Path(tempfile.mkdtemp(prefix="evos_palbase_"))

    base_pal, _bp, _bw, _bh, _bb, _bt = read_image(base_path)  # base 16-colour palette
    if ui_palette_path is not None:
        ui_pal = read_image(ui_palette_path)[0]               # UI/font palette for 1..15
        base_pal = list(base_pal[:1]) + list(ui_pal[1:16])    # keep clear colour at index 0
    opal, opix, w, h, _ob, _ot = read_image(override_path)
    px = [opal[i] for i in opix]                              # per-pixel RGB

    budget = 256 - base_index                                # photo colour slots
    if budget < 1:
        raise SystemExit(f"assetpack: palette_base {base_index} leaves no room for {override_path.name}")
    cnt: dict = {}
    for c in px:
        cnt[c] = cnt.get(c, 0) + 1
    remap: dict = {}
    colors = list(cnt)
    while len(colors) > budget:                              # merge least-frequent -> nearest
        colors.sort(key=lambda c: cnt[c])
        victim = colors[0]
        best = min(colors[1:], key=lambda c: (c[0]-victim[0])**2 + (c[1]-victim[1])**2 + (c[2]-victim[2])**2)
        remap[victim] = best
        cnt[best] += cnt[victim]
        del cnt[victim]
        colors = list(cnt)

    def resolve(c):
        while c in remap:
            c = remap[c]
        return c

    photo = list(cnt)
    pidx = {c: base_index + i for i, c in enumerate(photo)}
    palette = list(base_pal[:16]) + [(0, 0, 0)] * (base_index - 16) + photo
    idx_pixels = bytes(pidx[resolve(c)] for c in px)

    ui_tag = f"_ui{ui_palette_path.stem}" if ui_palette_path is not None else ""
    out = _RESERVED_TMPDIR / f"{base_path.stem}_{override_path.stem}_b{base_index}{ui_tag}.bmp"
    _write_indexed_bmp(out, w, h, idx_pixels, palette)
    return out


def apply_sprinter_overrides(entries: dict, manifest: Path) -> None:
    """Swap base graphics files for their `sprinter_<type>.N` overrides in place
    (§9.1). Keeps order/count/IDs (resources.h is unchanged), only the packed
    pixels differ. Sprite overrides must keep the base cell count or SPR_ ids
    would diverge from resources.h -- such an override is rejected with a warning.
    """
    overrides = parse_sprinter_overrides(manifest)
    if not overrides:
        return
    pal_base = parse_palette_base(manifest)          # {suffix N: base index}
    pal_ui = parse_palette_ui(manifest)              # {suffix N: UI-palette source}
    for kind in ("palette", "image", "sprite"):
        resolved = []
        for var_name, path in entries[kind]:
            ov = overrides.get(var_name)
            if ov is None:
                resolved.append((var_name, path))
                continue
            if not ov.exists():
                raise SystemExit(f"assetpack: sprinter override {var_name} -> {ov} not found")
            if kind == "sprite":
                base_n, _ = bmp_sprite_count(path)
                ov_n, _ = bmp_sprite_count(ov)
                if base_n is not None and ov_n != base_n:
                    warn(f"sprinter_sprite override '{ov.name}' has {ov_n} cells vs base "
                         f"'{path.name}' {base_n}; SPR_ ids would diverge -- override ignored")
                    resolved.append((var_name, path))
                    continue
            # palette_base.N: keep the base 16-colour palette at 0..15 and place
            # the override's richer colours at [B..255] (§9.1 partitioning), so the
            # game's UI/fill/sprites (indices 0..15) survive a 256-colour background.
            suffix = var_name.split(".", 1)[1] if "." in var_name else ""
            base_index = pal_base.get(suffix)
            if base_index is not None and kind in ("palette", "image"):
                ov = _reserved_layout_bmp(path, ov, base_index, pal_ui.get(suffix))
            resolved.append((var_name, ov))
        entries[kind] = resolved


def make_records(manifest: Path) -> list[Record]:
    entries, soundfx = parse_compile_bat(manifest)
    apply_sprinter_overrides(entries, manifest)
    records: list[Record] = []

    for rid, (_var, path) in enumerate(entries["palette"]):
        records.append(Record(TYPE_PAL, rid, 0, 0, 0, pack_palette(path), resource_name(path)))

    for rid, (_var, path) in enumerate(entries["image"]):
        payload, width, height, _keyed = pack_image(path)   # flat bundle: no hw_keyed flag
        records.append(Record(TYPE_IMG, rid, width, height, 0, payload, resource_name(path)))

    sprite_id = 0
    for _var, path in entries["sprite"]:
        sprite_records, declared_count = pack_sprites(path, sprite_id)
        records.extend(sprite_records)
        sprite_id += declared_count

    for rid, (_var, path) in enumerate(entries["music"]):
        if not path.exists():
            raise SystemExit(f"assetpack: {path}: music file not found")
        data = path.read_bytes()
        if not data:
            raise SystemExit(f"assetpack: {path}: empty music file")
        records.append(Record(TYPE_MUS, rid, 0, 0, 0, data, resource_name(path)))

    if soundfx is not None:
        if not soundfx.exists():
            raise SystemExit(f"assetpack: {soundfx}: soundfx bank not found")
        data = soundfx.read_bytes()
        if not data:
            raise SystemExit(f"assetpack: {soundfx}: empty soundfx bank")
        records.append(Record(TYPE_SFX, 0, 0, 0, 0, data, "BANK"))

    for rid, (_var, path) in enumerate(entries["sample"]):
        pcm, rate = parse_wav(path)
        if not pcm:
            raise SystemExit(f"assetpack: {path}: empty sample")
        records.append(Record(TYPE_SAM, rid, 0, 0, cbl_ctrl_for_rate(rate), pcm, resource_name(path)))

    seen = set()
    for rec in records:
        key = (rec.type, rec.id)
        if key in seen:
            raise SystemExit(f"assetpack: duplicate record type={rec.type} id={rec.id}")
        seen.add(key)

    return sorted(records, key=lambda rec: (rec.type, rec.id))


def write_bundle(records: list[Record], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)

    header_len = HEADER_SIZE + len(records) * RECORD_SIZE
    payload = bytearray(b"\0" * header_len)
    offsets: list[int] = []

    for rec in records:
        offsets.append(len(payload))
        payload += rec.data

    struct.pack_into(HEADER_FMT, payload, 0, MAGIC, VERSION, len(records), len(payload))

    for index, rec in enumerate(records):
        struct.pack_into(
            RECORD_FMT,
            payload,
            HEADER_SIZE + index * RECORD_SIZE,
            rec.type,
            rec.id,
            rec.width,
            rec.height,
            rec.reserved,
            offsets[index],
            len(rec.data),
        )

    tmp = output.with_name(output.name + ".tmp")
    tmp.write_bytes(payload)
    tmp.replace(output)


# =========================================================================
#  EVP1 -- paged asset bundle for the PRELOAD loader (O(1) access model).
# =========================================================================
#  Goal (HW_NOTES §15): the SDK reaches any asset in O(1) -- no runtime
#  search, no flat-pointer arithmetic across >64KB. Payloads are laid into
#  16KB DSS pages by resource class (EvoSDK model); per-type ID-indexed
#  metadata tables (small) are copied to RAM by the loader so `select_image`/
#  `pal_select`/... do `table_base + id*stride` then map one page.
#
#  File layout:
#    header (16 B):
#      u32 magic 'EVP1'
#      u8  num_pages         total payload pages (loader GetMem's this many)
#      u8  gfx_pages         #pages of the tile region == sprite-page base idx
#      u16 meta_off          file offset of the metadata blob
#      u16 meta_size
#      u16 pages_off         file offset of the page blobs (num_pages * 16KB)
#      u16 sprite_count
#      pad to 16
#    metadata blob (-> RAM):
#      u8 img_count;  img_count  * { u16 base_tile, u8 w_tiles, u8 h_tiles, u8 flags }
#                     flags bit0 = hw_keyed (#58 path). base_tile is a full u16.
#      u8 pal_count;  pal_count  * { u8 page, u16 offset }
#      u8 mus_count;  mus_count  * { u8 page, u16 offset, u16 len }
#      u8 smp_count;  smp_count  * { u8 page, u16 offset, u16 len, u8 cbl }
#      u8 sfx_present; [ u8 page, u16 offset, u16 len ]  ; #C000 AFX image
#    page blobs: num_pages * 16KB, in region order gfx|spr|pal|mus|smp|sfx.
#
#  Access (SDK, all O(1)):
#    image:   base_tile = img[id].base_tile; global = base_tile + tile;
#             page = page_table[global >> 8]; off = (global & 255) * 64.
#    sprite:  page = page_table[gfx_pages + (id >> 6)]; off = (id & 63) * 256.
#    palette: page = page_table[pal[id].page]; off = pal[id].offset.
#    sfx:     page = page_table[sfx.page]; entry #C000 init, #C003 play,
#             #C006 frame. Samples may span pages -- player walks them.
# =========================================================================

PAGE = 16384
# EVP2 (was EVP1): the IMG meta record gained a flags byte (4 -> 5 bytes), moving
# the hw_keyed flag out of base_tile. The magic bump makes a stale EVP1 bundle
# fail loudly at dss_exe time instead of being misread under the new layout.
EVP_MAGIC = b"EVP2"
EVP_HEADER_SIZE = 16
# Asset phys-page table in SDK SRAM is 200 entries (loader.asm EVO_PAGE_TABLE,
# #1A00..#1AC7). A bundle with more pages would overflow it into saved-state.
EVP_MAX_PAGES = 200


def _pad_to_page(blob: bytearray) -> None:
    if len(blob) % PAGE:
        blob += bytes(PAGE - (len(blob) % PAGE))


def build_paged(manifest: Path) -> tuple[bytes, bytes]:
    """Return (metadata_blob, page_data). page_data is num_pages*16KB in the
    region order gfx|spr|pal|mus|smp|sfx; metadata page indices are global."""
    entries, soundfx = parse_compile_bat(manifest)
    apply_sprinter_overrides(entries, manifest)
    color_keys = parse_color_keys(manifest)

    # --- tiles: concatenate every image's tiles, 256 tiles (16KB) per page ---
    gfx = bytearray()
    img_table: list[tuple[int, int, int, int]] = []  # (base_tile, w_tiles, h_tiles, flags)
    for var_name, path in entries["image"]:
        suffix = var_name.split(".", 1)[1] if "." in var_name else ""
        key = color_keys.get(suffix)               # K if declared color_key.N=K
        payload, w, h, keyed = pack_image(path, remap_key=key)
        base_tile = len(gfx) // 64
        # base_tile is a full u16 global tile index (EvoSDK IMGLIST.tile). The
        # hw_keyed flag rides a SEPARATE flags byte now, so the whole u16 range
        # is usable (capped in practice by the 200-page table -> ~51200 tiles).
        if base_tile > 0xFFFF:
            raise SystemExit(
                f"assetpack: {path}: base_tile {base_tile} exceeds u16 -- too "
                "much image tile data"
            )
        # hw_keyed if a color_key.N was declared OR the source (PNG) has alpha.
        flags = IMG_FLAG_HW_KEYED if keyed else 0
        # w/h tiles are u8 like makeresh: only used by draw_image, which can't
        # exceed the 40x32 screen anyway. Big tilesheets (e.g. an 1x258 mask
        # strip) are drawn by tile index, so clamp their unused dims rather than
        # wrap. h is no longer overloaded -- a clamped 255 is just a value now.
        img_table.append((base_tile, min(w // 8, 255), min(h // 8, 255), flags))
        gfx += payload
    _pad_to_page(gfx)
    gfx_pages = len(gfx) // PAGE

    # --- sprites: concatenate cells, 64 cells (16KB) per page ---
    spr = bytearray()
    sprite_id = 0
    for _v, path in entries["sprite"]:
        recs, declared = pack_sprites(path, sprite_id)
        for r in recs:
            spr += r.data
        sprite_id += declared
    sprite_count = sprite_id
    _pad_to_page(spr)
    spr_base = gfx_pages

    # --- palettes / music / samples / sfx: packed, never split an entry
    #     across a page boundary (so page+offset addressing is exact) ---
    def pack_region(items, base_page, *, align_each=False, align=1):
        blob = bytearray()
        table = []
        for data in items:
            if align_each and len(blob) % PAGE:
                _pad_to_page(blob)
            # Start each item on an `align`-byte boundary within its page. For CBL
            # samples (align=128) this lets the IRQ refill stream 128-byte bursts by
            # OUTI straight from paged VRAM with a page-cross check only ONCE per
            # burst (PAGE=16384 is 128-divisible, so a burst never straddles a page).
            if align > 1 and len(blob) % align:
                blob += b"\x80" * (align - len(blob) % align)   # #80 = CBL silence
            if len(blob) % PAGE + len(data) > PAGE and len(data) <= PAGE:
                _pad_to_page(blob)
            table.append((base_page + len(blob) // PAGE, len(blob) % PAGE, len(data)))
            blob += data
        _pad_to_page(blob)
        return blob, table

    pal_items = [pack_palette(p) for _v, p in entries["palette"]]
    pal_blob, pal_tab = pack_region(pal_items, spr_base + len(spr) // PAGE)

    mus_items = []
    for _v, path in entries["music"]:
        mus_items.append(pack_music_pt3(path))
    mus_base = spr_base + len(spr) // PAGE + len(pal_blob) // PAGE
    mus_blob, mus_tab = pack_region(mus_items, mus_base, align_each=True)

    smp_items, smp_cbl = [], []
    for _v, path in entries["sample"]:
        pcm, rate = parse_wav(path)
        smp_items.append(pcm)
        smp_cbl.append(cbl_ctrl_for_rate(rate))
    smp_base = mus_base + len(mus_blob) // PAGE
    smp_blob, smp_tab = pack_region(smp_items, smp_base, align=128)

    sfx_items = []
    if soundfx is not None:
        sfx_items.append(pack_soundfx_afx(soundfx))
    sfx_base = smp_base + len(smp_blob) // PAGE
    sfx_blob, sfx_tab = pack_region(sfx_items, sfx_base)

    page_data = bytes(gfx + spr + pal_blob + mus_blob + smp_blob + sfx_blob)
    num_pages = len(page_data) // PAGE
    if num_pages > EVP_MAX_PAGES:
        raise SystemExit(
            f"assetpack: bundle needs {num_pages} pages, exceeds the "
            f"{EVP_MAX_PAGES}-entry page table -- too many assets"
        )

    # --- metadata blob ---
    meta = bytearray()
    meta.append(len(img_table))
    for base_tile, wt, ht, flags in img_table:
        meta += struct.pack("<HBBB", base_tile, wt, ht, flags)
    meta.append(len(pal_tab))
    for page, off, _ln in pal_tab:
        meta += struct.pack("<BH", page, off)
    meta.append(len(mus_tab))
    for page, off, ln in mus_tab:
        meta += struct.pack("<BHH", page, off, ln)
    meta.append(len(smp_tab))
    for (page, off, ln), cbl in zip(smp_tab, smp_cbl):
        meta += struct.pack("<BHHB", page, off, ln, cbl)
    if sfx_tab:
        meta.append(1)
        page, off, ln = sfx_tab[0]
        meta += struct.pack("<BHH", page, off, ln)
    else:
        meta.append(0)

    header = bytearray(EVP_HEADER_SIZE)
    header[0:4] = EVP_MAGIC
    header[4] = num_pages
    header[5] = gfx_pages
    struct.pack_into("<H", header, 6, EVP_HEADER_SIZE)              # meta_off
    struct.pack_into("<H", header, 8, len(meta))                   # meta_size
    struct.pack_into("<H", header, 10, EVP_HEADER_SIZE + len(meta))  # pages_off
    struct.pack_into("<H", header, 12, sprite_count)
    return bytes(header) + bytes(meta), page_data


def write_paged_bundle(manifest: Path, output: Path) -> None:
    head_meta, page_data = build_paged(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_name(output.name + ".tmp")
    tmp.write_bytes(head_meta + page_data)
    tmp.replace(output)
    num_pages = page_data and len(page_data) // PAGE or 0
    print(f"assetpack: wrote {output} (EVP2, {num_pages} pages, "
          f"meta {len(head_meta) - EVP_HEADER_SIZE} B)")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build Sprinter EvoSDK asset bundle")
    parser.add_argument("manifest", type=Path, help="project compile.bat")
    parser.add_argument("-o", "--output", type=Path, default=Path("assets.dat"), help="output bundle")
    parser.add_argument("--paged", action="store_true",
                        help="emit the EVP1 paged bundle for the PRELOAD loader")
    parser.add_argument("--pal256", action="store_true",
                        help="256-colour sprites: only index 255 is transparent "
                             "(colours 0..254), instead of the 16-colour >=16 rule")
    args = parser.parse_args(argv)

    if args.pal256:
        global SPRITE_TRANSPARENT_MIN
        SPRITE_TRANSPARENT_MIN = 255

    if args.paged:
        write_paged_bundle(args.manifest, args.output)
        return 0

    records = make_records(args.manifest)
    write_bundle(records, args.output)
    print(f"assetpack: wrote {args.output} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
