#!/usr/bin/env python3
"""Strip alpha from AppIcon PNGs and save as truecolor RGB (required by App Store)."""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

ICONSET = Path(__file__).resolve().parent.parent / "Assets.xcassets" / "AppIcon.appiconset"
BACKGROUND = (0, 0, 0)


def write_rgb_png(path: Path, image: Image.Image) -> None:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.tobytes()
    raw = b"".join(b"\x00" + pixels[y * width * 3 : (y + 1) * width * 3] for y in range(height))

    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        content = chunk_type + data
        return struct.pack(">I", len(data)) + content + struct.pack(">I", zlib.crc32(content) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def flatten_icon(path: Path) -> None:
    image = Image.open(path)
    if image.mode in ("RGBA", "LA", "P"):
        image = image.convert("RGBA")
        background = Image.new("RGB", image.size, BACKGROUND)
        background.paste(image, mask=image.split()[-1])
        image = background
    write_rgb_png(path, image)


def main() -> int:
    if not ICONSET.is_dir():
        print(f"warning: AppIcon set not found at {ICONSET}", file=sys.stderr)
        return 0

    for icon in sorted(ICONSET.glob("*.png")):
        flatten_icon(icon)
        print(f"fixed {icon.name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
