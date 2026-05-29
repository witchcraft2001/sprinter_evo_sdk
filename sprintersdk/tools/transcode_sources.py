#!/usr/bin/env python3
"""Copy project C sources to a build tree using a target single-byte encoding."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


TEXT_SUFFIXES = {".c", ".h"}
SKIP_DIRS = {".git", "_build"}


def should_skip_dir(path: Path, dst: Path) -> bool:
    if path.name in SKIP_DIRS:
        return True
    try:
        path.relative_to(dst)
        return True
    except ValueError:
        return False


def transcode_file(src: Path, dst: Path, encoding: str) -> None:
    try:
        text = src.read_text(encoding="utf-8")
        data = text.encode(encoding)
    except UnicodeEncodeError as exc:
        bad = text[exc.start:exc.end]
        raise SystemExit(
            f"transcode_sources: {src}: cannot encode {bad!r} to {encoding} "
            f"at character {exc.start}"
        ) from exc
    except UnicodeDecodeError as exc:
        raise SystemExit(f"transcode_sources: {src}: expected UTF-8 source") from exc

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)


def copy_tree(src: Path, dst: Path, encoding: str) -> int:
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)

    count = 0
    for path in src.rglob("*"):
        if path.is_dir():
            continue
        if any(should_skip_dir(parent, dst) for parent in path.parents):
            continue
        rel = path.relative_to(src)
        if path.suffix.lower() in TEXT_SUFFIXES:
            transcode_file(path, dst / rel, encoding)
            count += 1

    return count


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path, help="project source directory")
    parser.add_argument("dst", type=Path, help="encoded build source directory")
    parser.add_argument("--encoding", default="cp866", help="target encoding")
    args = parser.parse_args(argv)

    src = args.src.resolve()
    dst = args.dst.resolve()
    count = copy_tree(src, dst, args.encoding)
    print(f"transcode_sources: copied {count} text source(s) to {dst} ({args.encoding})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
