#!/usr/bin/env python3
from __future__ import annotations

import os
import struct
import zlib


def _png_rgba(width: int, height: int, rgba: tuple[int, int, int, int]) -> bytes:
    r, g, b, a = rgba
    raw = bytearray()
    row = bytes([r, g, b, a]) * width
    for _ in range(height):
        raw.append(0)  # filter type 0
        raw.extend(row)
    compressed = zlib.compress(bytes(raw), level=9)

    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + chunk_type
            + data
            + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", ihdr),
            chunk(b"IDAT", compressed),
            chunk(b"IEND", b""),
        ]
    )


def main() -> int:
    out_path = os.path.join(
        "MouseManager",
        "Assets.xcassets",
        "AppIcon.appiconset",
        "icon_1024.png",
    )
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    # Simple modern-ish dark icon background; user can replace later.
    png = _png_rgba(1024, 1024, (32, 34, 37, 255))
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

