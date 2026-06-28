#!/usr/bin/env python3
"""Create a Sprinter DSS EXE from Intel HEX, optionally appending assets."""

from __future__ import annotations

import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


EXE_SIGNATURE = b"EXE"
EXE_VERSION = 1
EXE_HEADER_SIZE = 512
DSS_MIN_LOAD = 0x4100
# di(1) + ld hl,nn(3) + ld de,nn(3) + ld bc,nn(3) + ldir(2) + ld sp,nn(3) + jp nn(3)
LOW_COPY_LOADER_SIZE = 18

# --- Monoblock PRELOAD layout (HW_NOTES §9.2, loader.asm) ---
PAGE = 0x4000                      # 16 KB window/page
MONOBLOCK_CODE_CHUNKS = 4          # chunk0=#0000-#3FFF(hot/SRAM),1=WIN1,2=WIN2,3=WIN3
MONOBLOCK_HOT_SIZE = 0x4000        # bytes of chunk0 LDIR'd into SRAM
MONOBLOCK_ENTRY = 0x2400           # crt0 _entry (runs in SRAM after cache-on)
# The loader runs in WIN2 -- the canonical DSS program window (DSS/BIOS use WIN0
# system + WIN1 scratch, so SetVMod doesn't clobber it). See loader.asm.
LOADER_LOAD = 0x8100
LOADER_SP = 0xBFFF
MINIHDR_SIZE = 16
MINIHDR_MAGIC = ord("L")
MINIHDR_FLAG_PACKED = 0x01
# Fixed-size title field that follows the mini-header in the monoblock body. The
# loader reads exactly this many bytes and prints "Loading <title>" (the field is
# NUL-padded, so it is also NUL-terminated for the loader's puts). MUST match
# TITLE_LEN in loader.asm.
MONOBLOCK_TITLE_LEN = 32
# EVP2: IMG meta records are 5 bytes (base_tile, w, h, flags). EVP1 bundles use
# the old 4-byte record and must be rejected so they aren't misread.
EVP_MAGIC = b"EVP2"
EVP_HEADER_SIZE = 16
# SDK SRAM table region (loader.asm EVO_*): #1A00 page table (200 B, #1A00-#1AC7) /
# #1AC8 vmode / #1B00 EVP1 meta, up to the stack at #2000. SDK code+data must stay
# below it and C must start at/after #2400 -- so #1A00..#23FF must be empty in the image.
EVO_TABLE_REGION = 0x1A00
EVO_TABLE_END = 0x2400              # exclusive (covers tables + the 1 KB stack)
EVO_META_MAX = 0x400               # #1B00..#1EFF
MAX_ASSET_PAGES = 200              # page_table capacity (#1A00-#1AC7); 200*16K = 3.2 MB


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


def parse_map_symbols(path: Path) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in path.read_text(encoding="ascii", errors="ignore").splitlines():
        parts = line.split()
        if len(parts) == 2 and len(parts[0]) == 4:
            try:
                symbols[parts[1]] = int(parts[0], 16)
            except ValueError:
                continue
    return symbols


def map_image_top(path: Path) -> tuple[str, int]:
    """Highest byte address (exclusive end) occupied by any linker area.

    Returns (area_name, end_addr). The IHX holds only emitted bytes, so it
    hides a BSS/_DATA area that spills past #FFFF; this reads the .map areas
    (`<name> <addr_hex> <size_hex> = <dec>. bytes (attrs)`) to catch it.
    """
    top_name, top_end = "", 0
    for line in path.read_text(encoding="ascii", errors="ignore").splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[3] == "=":
            try:
                end = int(parts[1], 16) + int(parts[2], 16)
            except ValueError:
                continue
            if end > top_end:
                top_name, top_end = parts[0], end
    return top_name, top_end


def patch_u16(image: bytearray, load: int, address: int, value: int, name: str) -> None:
    if not 0 <= value <= 0xFFFF:
        raise SystemExit(f"dss_exe: {name} patch value 0x{value:X} is outside u16")
    offset = address - load
    if offset < 0 or offset + 2 > len(image):
        raise SystemExit(
            f"dss_exe: symbol {name} at 0x{address:04X} is outside image "
            f"loaded at 0x{load:04X} ({len(image)} bytes)"
        )
    struct.pack_into("<H", image, offset, value)


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


def image_from_zero(data: dict[int, int]) -> bytes:
    """Flatten the IHX into a byte image starting at 0x0000 (monoblock layout)."""
    if not data:
        raise SystemExit("dss_exe: IHX contains no data")
    max_addr = max(data)
    out = bytearray(max_addr + 1)
    for addr, byte in data.items():
        out[addr] = byte
    return bytes(out)


def parse_evp1(bundle: bytes) -> tuple[bytes, list[bytes]]:
    """Split an EVP1 paged bundle into (meta_blob, [16 KB data pages]).

    meta_blob = EVP1 header + metadata region (everything before pages_off);
    copied to EVO_META. Data pages map 1:1 to physical pages via the page table.
    """
    if bundle[:4] != EVP_MAGIC:
        raise SystemExit("dss_exe: --assets is not an EVP2 paged bundle (rebuild with "
                         "assetpack --paged; a stale EVP1 bundle is no longer accepted)")
    # EVP1 header (assetpack write_paged_bundle): magic[0:4], num_pages[4],
    # gfx_pages[5], meta_off[6:8], meta_size[8:10], pages_off[10:12], sprite_count[12:14].
    num_pages = bundle[4]
    pages_off = struct.unpack_from("<H", bundle, 10)[0]
    # meta blob = EVP1 header + metadata tables (the SDK needs the header's
    # internal table offsets), i.e. everything before the page region.
    meta_blob = bundle[:pages_off]
    pages_region = bundle[pages_off:]
    pages: list[bytes] = []
    for i in range(num_pages):
        chunk = pages_region[i * PAGE:(i + 1) * PAGE]
        if len(chunk) < PAGE:
            chunk = chunk + bytes(PAGE - len(chunk))
        pages.append(chunk)
    return meta_blob, pages


def run_tool(args: list[str]) -> bytes:
    try:
        result = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        output = exc.stdout.decode("utf-8", errors="replace") if exc.stdout else ""
        raise SystemExit(f"dss_exe: tool failed: {' '.join(args)}\n{output}") from exc
    return result.stdout


def pack_page(mhmt: Path, page: bytes, index: int, tmpdir: Path) -> tuple[int, bytes]:
    if len(page) != PAGE:
        raise SystemExit(f"dss_exe: internal error: page {index} is {len(page)} bytes")

    # All-zero page: emit size 0 (no payload). The loader zero-fills it directly,
    # skipping the HRUST depacker -- which mis-decodes the degenerate "16K of
    # zeros" stream by reading past it into the uninitialized destination page.
    if not any(page):
        return 0, b""

    raw = tmpdir / f"page{index:03d}.raw"
    packed = tmpdir / f"page{index:03d}.hst"
    depacked = tmpdir / f"page{index:03d}.dpk"

    raw.write_bytes(page)
    run_tool([str(mhmt), "-hst", "-zxh", str(raw), str(packed)])
    packed_data = packed.read_bytes()

    if len(packed_data) >= PAGE:
        return PAGE, page

    run_tool([str(mhmt), "-d", "-hst", "-zxh", str(packed), str(depacked)])
    if depacked.read_bytes() != page:
        raise SystemExit(f"dss_exe: mhmt verification failed for page {index}")

    return len(packed_data), packed_data


def pack_pages(pages: list[bytes], mhmt: Path) -> tuple[list[int], list[bytes], int]:
    if not mhmt.is_file() or not os.access(mhmt, os.X_OK):
        raise SystemExit(f"dss_exe: mhmt is not executable: {mhmt}")

    sizes: list[int] = []
    payloads: list[bytes] = []
    saved = 0
    with tempfile.TemporaryDirectory(prefix="spevo-exe-pack-") as tmp:
        tmpdir = Path(tmp)
        for index, page in enumerate(pages):
            size, payload = pack_page(mhmt, page, index, tmpdir)
            sizes.append(size)
            payloads.append(payload)
            saved += PAGE - len(payload)
    return sizes, payloads, saved


def read_manifest_title(manifest: Path | None) -> bytes:
    """Extract `set title=...` from a compile.bat manifest as a display string.

    Returns the title bytes (quotes/whitespace stripped), truncated to fit the
    NUL-terminated MONOBLOCK_TITLE_LEN field. Bytes are kept verbatim (the DSS
    text console renders them) -- ASCII titles work as-is. Empty on no title.
    """
    if not manifest or not manifest.exists():
        return b""
    raw = manifest.read_bytes()
    for line in raw.splitlines():
        m = re.match(rb"\s*set\s+title\s*=(.*)$", line, re.IGNORECASE)
        if not m:
            continue
        value = m.group(1).strip()
        if len(value) >= 2 and value[:1] == b'"' and value[-1:] == b'"':
            value = value[1:-1]
        value = value.strip()
        # Leave room for the NUL terminator inside the fixed field.
        return value[: MONOBLOCK_TITLE_LEN - 1]
    return b""


def build_monoblock(
    code: bytes,
    loader: bytes,
    assets: bytes,
    entry: int,
    *,
    tables: int = EVO_TABLE_REGION,
    title: bytes = b"",
    pack: bool = False,
    mhmt: Path | None = None,
) -> tuple[bytes, int, int, int, int]:
    """Assemble a DSS PRELOAD monoblock EXE the loader.asm reads.

    Unpacked body:
        [16B mini-header][32B title][K x 16 KB code chunks][meta][M x 16 KB pages].
    Packed body:
        [16B mini-header][32B title][(K+M) x u16 payload sizes]
        [K code payloads][meta][M asset payloads].

    The title field (NUL-padded `set title=` from compile.bat) is read by the
    loader right after the mini-header and printed verbatim as the loading banner
    (the title is the full message, e.g. "CODENAME ROBO IS LOADING").

    A payload size of 0x4000 means raw 16 KB; any smaller size is HRUST .hst.
    """
    if assets:
        meta_blob, data_pages = parse_evp1(assets)
    else:
        meta_blob, data_pages = b"", []

    # Code image padded to K full 16 KB chunks from 0x0000.
    chunks_needed = (len(code) + PAGE - 1) // PAGE
    k = max(MONOBLOCK_CODE_CHUNKS, chunks_needed)
    image = code + bytes(k * PAGE - len(code))
    code_pages = [image[i * PAGE:(i + 1) * PAGE] for i in range(k)]

    # SDK code+data must stay below the loader's table region; C starts at the
    # entry (CODE_LOC) -- so nothing should occupy [tables, entry) in the image
    # (tables + stack, the RAM the loader fills). Both bounds auto-raise with the
    # layout (sprinter.mk / layout.py); tables defaults to the #1A00 floor.
    region = image[tables:entry]
    if any(region):
        raise SystemExit(
            f"dss_exe: image has data in the reserved SDK region "
            f"0x{tables:04X}-0x{entry - 1:04X} (tables + stack); "
            f"SDK code+data is too large for the #0000-0x{tables - 1:04X} SRAM window"
        )

    m = len(data_pages)
    if m > MAX_ASSET_PAGES:
        raise SystemExit(
            f"dss_exe: {m} asset pages exceed the {MAX_ASSET_PAGES}-entry page table"
        )
    if len(meta_blob) > EVO_META_MAX:
        raise SystemExit(
            f"dss_exe: EVP1 meta {len(meta_blob)} B exceeds the 0x{EVO_META_MAX:X} "
            "SRAM meta window (#1B00-#1EFF)"
        )

    minihdr = bytearray(MINIHDR_SIZE)
    minihdr[0] = MINIHDR_MAGIC
    minihdr[1] = k
    minihdr[2] = m
    if pack:
        minihdr[3] = MINIHDR_FLAG_PACKED
    struct.pack_into("<H", minihdr, 4, len(meta_blob))
    struct.pack_into("<H", minihdr, 6, MONOBLOCK_HOT_SIZE)
    struct.pack_into("<H", minihdr, 8, entry)

    # Fixed NUL-padded title field, read by the loader right after the mini-header
    # to print "Loading <title>". MONOBLOCK_TITLE_LEN must match loader.asm.
    title_field = title[: MONOBLOCK_TITLE_LEN - 1].ljust(MONOBLOCK_TITLE_LEN, b"\x00")

    header = make_header(LOADER_LOAD, LOADER_LOAD, LOADER_SP, loader_size=len(loader))
    saved = 0

    if pack:
        if mhmt is None:
            raise SystemExit("dss_exe: --pack requires --mhmt <path>")
        sizes, payloads, saved = pack_pages(code_pages + data_pages, mhmt)
        size_table = bytearray()
        for size in sizes:
            if not 0 <= size <= PAGE:        # 0 = all-zero page (loader zero-fills)
                raise SystemExit(f"dss_exe: invalid packed payload size {size}")
            size_table += struct.pack("<H", size)
        body = (
            bytes(minihdr)
            + title_field
            + bytes(size_table)
            + b"".join(payloads[:k])
            + meta_blob
            + b"".join(payloads[k:])
        )
    else:
        body = bytes(minihdr) + title_field + image + meta_blob + b"".join(data_pages)

    return header + loader + body, k, m, len(meta_blob), saved


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="input .ihx")
    parser.add_argument("output", type=Path, help="output .exe")
    parser.add_argument("--load", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--entry", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--stack", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--tables", type=lambda value: int(value, 0),
                        default=EVO_TABLE_REGION,
                        help="base of the loader-filled table region (auto-raised "
                             "EVO_TABLES; floor 0x1A00). Image must be empty in "
                             "[tables, entry).")
    parser.add_argument("--assets", type=Path, help="append raw/packed assets after code")
    parser.add_argument("--map", type=Path, help="linker .map for runtime symbol patching")
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
    parser.add_argument(
        "--monoblock",
        action="store_true",
        help="build a DSS PRELOAD monoblock EXE (loader + paged code/assets inside)",
    )
    parser.add_argument("--loader", type=Path, help="assembled PRELOAD loader binary")
    parser.add_argument(
        "--manifest",
        type=Path,
        help="compile.bat; its `set title=` is printed verbatim by the loader as the banner",
    )
    parser.add_argument(
        "--pack",
        action="store_true",
        help="HRUST-pack monoblock code/asset pages; raw pages are kept when not smaller",
    )
    parser.add_argument(
        "--mhmt",
        type=Path,
        default=Path(__file__).resolve().parent / "bin" / "mhmt",
        help="path to mhmt for --pack",
    )
    args = parser.parse_args(argv)

    if args.monoblock:
        if not args.loader:
            raise SystemExit("dss_exe: --monoblock requires --loader <loader.bin>")
        if args.map:
            area, end = map_image_top(args.map)
            if end > 0x10000:
                raise SystemExit(
                    f"dss_exe: linker area {area} ends at 0x{end:05X}, past the 64K "
                    f"address ceiling 0x10000 (overflow {end - 0x10000} B). C code+data "
                    f"exceeds the #2400-#FFFF budget -- reduce code or wait for Phase 2 "
                    f"(SDCC 4.5.0). The IHX alone hides this (BSS is not emitted)."
                )
        code = image_from_zero(parse_ihx(args.input))
        loader = args.loader.read_bytes()
        assets = args.assets.read_bytes() if args.assets else b""
        title = read_manifest_title(args.manifest)
        exe, k, m, meta, saved = build_monoblock(
            code,
            loader,
            assets,
            args.entry,
            tables=args.tables,
            title=title,
            pack=args.pack,
            mhmt=args.mhmt,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        tmp = args.output.with_name(args.output.name + ".tmp")
        tmp.write_bytes(exe)
        tmp.replace(args.output)
        pack_info = f", packed saved={saved} B" if args.pack else ""
        title_info = f', title="{title.decode("latin-1")}"' if title else ""
        print(
            f"dss_exe: wrote {args.output} (mode=monoblock, loader={len(loader)} B, "
            f"code={len(code)} B -> {k} chunks, meta={meta} B, asset_pages={m}, "
            f"total={len(exe)} B{pack_info}{title_info})"
        )
        return 0

    code = bytearray(contiguous_image(parse_ihx(args.input), args.load))
    assets = args.assets.read_bytes() if args.assets else b""
    assets_address: int | None = None

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
        assets_address = source + len(code)
        direct_end = assets_address + len(assets)
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
        exe = make_header(loader_load, loader_load, args.stack) + loader + bytes(code) + assets
        mode = (
            f"low-loader load=0x{loader_load:04X}, copy=0x{source:04X}->0x{args.load:04X}, "
            f"entry=0x{args.entry:04X}"
        )
    else:
        if args.load < DSS_MIN_LOAD:
            mode = "format-only low-load"
        else:
            mode = "direct"
        assets_address = args.load + len(code)
        exe = make_header(args.load, args.entry, args.stack) + bytes(code) + assets

    if args.map and assets:
        if assets_address is None:
            raise SystemExit("dss_exe: internal error: assets address was not calculated")
        symbols = parse_map_symbols(args.map)
        patched = []
        if "_evos_assets_ptr" in symbols:
            patch_u16(code, args.load, symbols["_evos_assets_ptr"], assets_address, "_evos_assets_ptr")
            patched.append(f"_evos_assets_ptr=0x{assets_address:04X}")
        if "_evos_assets_len" in symbols:
            patch_u16(code, args.load, symbols["_evos_assets_len"], len(assets), "_evos_assets_len")
            patched.append(f"_evos_assets_len={len(assets)}")
        if patched:
            if args.load < DSS_MIN_LOAD and not args.allow_low_load:
                loader = make_low_copy_loader(
                    loader_load=args.low_loader_load,
                    source=args.low_loader_load + LOW_COPY_LOADER_SIZE,
                    target=args.load,
                    size=len(code),
                    stack=args.stack,
                    entry=args.entry,
                )
                exe = make_header(args.low_loader_load, args.low_loader_load, args.stack) + loader + bytes(code) + assets
            else:
                exe = make_header(args.load, args.entry, args.stack) + bytes(code) + assets
            mode += ", patched " + ", ".join(patched)

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
