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
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

try:
    from resgen import parse_compile_bat, resource_name, bmp_sprite_count, warn
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from resgen import parse_compile_bat, resource_name, bmp_sprite_count, warn


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
DEFAULT_PT3_PLAYER = Path(__file__).resolve().parent.parent / "pt3play.asm"
DEFAULT_AFX_PLAYER = Path(__file__).resolve().parent.parent / "ayfxplay.asm"


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
    if bpp not in (4, 8):
        raise SystemExit(f"assetpack: {path}: only 4/8bpp BMP is supported")

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


def pack_palette(path: Path) -> bytes:
    palette, _pixels, _width, _height, _bpp = read_bmp(path)
    payload = bytearray()
    payload += struct.pack("<H", len(palette))
    for r, g, b in palette:
        payload += bytes((r, g, b))
    return bytes(payload)


def pack_image(path: Path) -> tuple[bytes, int, int]:
    _palette, pixels, width, height, _bpp = read_bmp(path)
    if (width & 7) or (height & 7):
        raise SystemExit(f"assetpack: {path}: image dimensions must be 8px aligned")

    out = bytearray()
    for ty in range(0, height, 8):
        for tx in range(0, width, 8):
            for row in range(8):
                off = (ty + row) * width + tx
                out += pixels[off:off + 8]

    return bytes(out), width, height


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

    _palette, pixels, width, height, _bpp = read_bmp(path)
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
                pixel = pixels[(sy + y) * width + sx + x]
                payload[y * 16 + x] = 0xFF if pixel >= 16 else pixel

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
    # HW_NOTES.md §6.1: CBL rate control bytes are #D9/#DA/#DB for
    # roughly 11/15/21 kHz; bit4 enables the #FE.7 half-FIFO indicator.
    if rate <= 12000:
        return 0xD9
    if rate <= 17000:
        return 0xDA
    return 0xDB


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


def make_records(manifest: Path) -> list[Record]:
    entries, soundfx = parse_compile_bat(manifest)
    records: list[Record] = []

    for rid, (_var, path) in enumerate(entries["palette"]):
        records.append(Record(TYPE_PAL, rid, 0, 0, 0, pack_palette(path), resource_name(path)))

    for rid, (_var, path) in enumerate(entries["image"]):
        payload, width, height = pack_image(path)
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
#      u8 img_count;  img_count  * { u16 base_tile, u8 w_tiles, u8 h_tiles }
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
EVP_MAGIC = b"EVP1"
EVP_HEADER_SIZE = 16


def _pad_to_page(blob: bytearray) -> None:
    if len(blob) % PAGE:
        blob += bytes(PAGE - (len(blob) % PAGE))


def build_paged(manifest: Path) -> tuple[bytes, bytes]:
    """Return (metadata_blob, page_data). page_data is num_pages*16KB in the
    region order gfx|spr|pal|mus|smp|sfx; metadata page indices are global."""
    entries, soundfx = parse_compile_bat(manifest)

    # --- tiles: concatenate every image's tiles, 256 tiles (16KB) per page ---
    gfx = bytearray()
    img_table: list[tuple[int, int, int]] = []      # (base_tile, w_tiles, h_tiles)
    for _v, path in entries["image"]:
        payload, w, h = pack_image(path)
        # base_tile is u16 (global tile index, EvoSDK IMGLIST.tile). w/h tiles
        # are u8 like makeresh: only used by draw_image, which can't exceed the
        # 40x32 screen anyway. Big tilesheets (e.g. an 1x258 mask strip) are
        # drawn by tile index, so clamp their unused dims rather than wrap.
        img_table.append((len(gfx) // 64, min(w // 8, 255), min(h // 8, 255)))
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
    def pack_region(items, base_page, *, align_each=False):
        blob = bytearray()
        table = []
        for data in items:
            if align_each and len(blob) % PAGE:
                _pad_to_page(blob)
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
    smp_blob, smp_tab = pack_region(smp_items, smp_base)

    sfx_items = []
    if soundfx is not None:
        sfx_items.append(pack_soundfx_afx(soundfx))
    sfx_base = smp_base + len(smp_blob) // PAGE
    sfx_blob, sfx_tab = pack_region(sfx_items, sfx_base)

    page_data = bytes(gfx + spr + pal_blob + mus_blob + smp_blob + sfx_blob)
    num_pages = len(page_data) // PAGE

    # --- metadata blob ---
    meta = bytearray()
    meta.append(len(img_table))
    for base_tile, wt, ht in img_table:
        meta += struct.pack("<HBB", base_tile, wt, ht)
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
    print(f"assetpack: wrote {output} (EVP1, {num_pages} pages, "
          f"meta {len(head_meta) - EVP_HEADER_SIZE} B)")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build Sprinter EvoSDK asset bundle")
    parser.add_argument("manifest", type=Path, help="project compile.bat")
    parser.add_argument("-o", "--output", type=Path, default=Path("assets.dat"), help="output bundle")
    parser.add_argument("--paged", action="store_true",
                        help="emit the EVP1 paged bundle for the PRELOAD loader")
    args = parser.parse_args(argv)

    if args.paged:
        write_paged_bundle(args.manifest, args.output)
        return 0

    records = make_records(args.manifest)
    write_bundle(records, args.output)
    print(f"assetpack: wrote {args.output} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
